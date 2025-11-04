#!/usr/bin/env python3
"""
IMAP Message Date Synchronizer

This script resets the internal date (INTERNALDATE) of IMAP messages to match
their Date header. Since IMAP doesn't allow direct modification of INTERNALDATE,
the script re-uploads each message with the correct date and removes the original.

This script supports two connection modes:
1. Network mode: Connect to remote IMAP server via SSL (--server, --username, --password)
2. Local process mode: Spawn local Dovecot IMAP process (--process)

WARNING: This modifies your mailbox. Always run in --dry-run mode first!
"""

import imaplib
import email
import email.utils
import argparse
import logging
import sys
import re
from datetime import datetime, timezone
from typing import List, Tuple, Optional
from dataclasses import dataclass


@dataclass
class MessageStats:
    """Track statistics for processing."""
    total: int = 0
    skipped_no_date: int = 0
    skipped_matching: int = 0
    skipped_error: int = 0
    updated: int = 0
    would_update: int = 0


class IMAPDateSynchronizer:
    """Synchronize IMAP message internal dates with Date headers."""

    def __init__(self, server: Optional[str] = None, port: int = 993,
                 username: Optional[str] = None, password: Optional[str] = None,
                 process: Optional[str] = None,
                 dry_run: bool = True, skip_matching: bool = True):
        self.server = server
        self.port = port
        self.username = username
        self.password = password
        self.process = process
        self.dry_run = dry_run
        self.skip_matching = skip_matching
        self.logger = logging.getLogger(__name__)
        self.imap: Optional[imaplib.IMAP4] = None

    def connect(self) -> None:
        """Connect and authenticate to IMAP server or spawn local process."""
        if self.process:
            # Local process mode (Dovecot)
            self.logger.info(f"Spawning local IMAP process: {self.process}")
            self.imap = imaplib.IMAP4_stream(self.process)
            self.logger.info("Connected to local IMAP process (authentication handled by process)")
        else:
            # Network mode
            self.logger.info(f"Connecting to {self.server}:{self.port}")
            self.imap = imaplib.IMAP4_SSL(self.server, self.port)
            self.imap.login(self.username, self.password)
            self.logger.info(f"Logged in as {self.username}")

    def disconnect(self) -> None:
        """Disconnect from IMAP server."""
        if self.imap:
            try:
                self.imap.logout()
                self.logger.info("Disconnected from server")
            except:
                pass

    def list_mailboxes(self) -> List[str]:
        """List all available mailboxes."""
        status, mailboxes = self.imap.list()
        if status != 'OK':
            raise RuntimeError(f"Failed to list mailboxes: {status}")

        result = []
        for mailbox in mailboxes:
            # Parse mailbox name from IMAP LIST response
            # Format: (flags) "delimiter" "name"
            match = re.search(rb'\) "([^"]*)" "?([^"]+)"?$', mailbox)
            if match:
                name = match.group(2).decode('utf-8')
                result.append(name)
        return result

    def parse_internaldate(self, date_str: str) -> datetime:
        """Parse IMAP INTERNALDATE to datetime object.

        Format: "DD-Mon-YYYY HH:MM:SS +ZZZZ"
        Example: "17-Jul-1996 02:44:25 -0700"
        """
        from datetime import timedelta

        # Parse using regex since imaplib.Internaldate2tuple expects full IMAP response
        # Format: DD-Mon-YYYY HH:MM:SS +ZZZZ
        pattern = r'(\d{1,2})-(\w+)-(\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s+([+-]\d{4})'
        match = re.match(pattern, date_str)

        if not match:
            raise ValueError(f"Invalid INTERNALDATE format: {date_str}")

        day, month_name, year, hour, minute, second, tz_str = match.groups()

        # Convert month name to number
        month_names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
        try:
            month = month_names.index(month_name) + 1
        except ValueError:
            raise ValueError(f"Invalid month name: {month_name}")

        # Parse timezone offset
        tz_sign = 1 if tz_str[0] == '+' else -1
        tz_hours = int(tz_str[1:3])
        tz_minutes = int(tz_str[3:5])
        offset_seconds = tz_sign * (tz_hours * 3600 + tz_minutes * 60)
        tz_offset = timezone(timedelta(seconds=offset_seconds))

        # Create datetime
        dt = datetime(int(year), month, int(day), int(hour), int(minute), int(second),
                     tzinfo=tz_offset)

        return dt

    def format_imap_date(self, dt: datetime) -> str:
        """Format datetime to IMAP INTERNALDATE format.

        Format: "DD-Mon-YYYY HH:MM:SS +ZZZZ"
        """
        month_names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

        # Get timezone offset
        if dt.tzinfo:
            offset = dt.utcoffset()
            offset_seconds = int(offset.total_seconds())
            offset_hours = abs(offset_seconds) // 3600
            offset_minutes = (abs(offset_seconds) % 3600) // 60
            tz_sign = '+' if offset_seconds >= 0 else '-'
            tz_str = f"{tz_sign}{offset_hours:02d}{offset_minutes:02d}"
        else:
            tz_str = "+0000"

        return f'"{dt.day:02d}-{month_names[dt.month-1]}-{dt.year} {dt.hour:02d}:{dt.minute:02d}:{dt.second:02d} {tz_str}"'

    def parse_fetch_response(self, data: list) -> Tuple[Optional[str], Optional[bytes], Optional[str]]:
        """Parse IMAP FETCH response to extract INTERNALDATE, message, and FLAGS.

        Returns: (internaldate_str, message_bytes, flags_str)
        """
        if not data or not data[0]:
            self.logger.debug("Empty FETCH response")
            return None, None, None

        # Response format can be:
        # [(b'1 (UID ... INTERNALDATE "..." BODY[] {size}', b'message...'), b')']
        # OR
        # [b'1 (UID ... INTERNALDATE "..." BODY[] "message")', b')']

        parts = data[0]

        # Handle both tuple and bytes responses
        if isinstance(parts, tuple):
            if len(parts) < 2:
                self.logger.debug(f"Unexpected tuple length: {len(parts)}")
                return None, None, None
            header_bytes = parts[0]
            message = parts[1]
        elif isinstance(parts, bytes):
            # All in one bytes object - need to split
            header_bytes = parts
            message = None
        else:
            self.logger.debug(f"Unexpected response type: {type(parts)}")
            return None, None, None

        # Decode header
        try:
            header = header_bytes.decode('utf-8', errors='ignore')
        except:
            header = str(header_bytes)

        self.logger.debug(f"FETCH header: {header[:200]}")

        # Extract INTERNALDATE
        internaldate_match = re.search(r'INTERNALDATE "([^"]+)"', header)
        internaldate = internaldate_match.group(1) if internaldate_match else None

        if not internaldate:
            self.logger.debug(f"Could not find INTERNALDATE in: {header}")

        # Extract FLAGS
        flags_match = re.search(r'FLAGS \(([^)]*)\)', header)
        flags = flags_match.group(1) if flags_match else ''

        # If message is None, try to extract from header
        if message is None:
            # Look for BODY[] content in the same bytes
            body_match = re.search(rb'BODY\[\] \{(\d+)\}', header_bytes)
            if body_match:
                # Message follows after the header
                # This is complex - imaplib should handle this
                self.logger.warning("Message embedded in header - using raw response")
                # Try to get it from the raw data
                for item in data:
                    if isinstance(item, tuple) and len(item) > 1:
                        message = item[1]
                        break

        return internaldate, message, flags

    def normalize_flags(self, flags: str) -> str:
        r"""Normalize flags for APPEND command.

        Remove \Recent flag as it cannot be set by clients.
        """
        flag_list = [f.strip() for f in flags.split() if f.strip()]
        # Remove \Recent
        flag_list = [f for f in flag_list if f.lower() != r'\recent']
        return ' '.join(flag_list)

    def dates_match(self, date1: datetime, date2: datetime, tolerance_seconds: int = 1) -> bool:
        """Compare two dates with tolerance for rounding differences."""
        diff = abs((date1 - date2).total_seconds())
        return diff <= tolerance_seconds

    def process_message(self, uid: bytes, mailbox: str) -> Tuple[bool, str]:
        """Process a single message.

        Returns: (success, status_message)
        """
        try:
            # Fetch message data
            status, data = self.imap.uid('fetch', uid, '(INTERNALDATE BODY.PEEK[] FLAGS)')
            if status != 'OK':
                return False, f"FETCH failed: {status}"

            # Debug raw response
            if hasattr(self, 'debug_fetch') and self.debug_fetch:
                self.logger.info(f"  Raw FETCH response for UID {uid.decode()}:")
                for i, item in enumerate(data):
                    self.logger.info(f"    data[{i}]: type={type(item)}, len={len(item) if hasattr(item, '__len__') else 'N/A'}")
                    if isinstance(item, tuple):
                        for j, subitem in enumerate(item):
                            preview = str(subitem[:100] if isinstance(subitem, bytes) else subitem)
                            self.logger.info(f"      [{j}]: {type(subitem)} - {preview}")
                    else:
                        preview = str(item[:100] if isinstance(item, bytes) else item)
                        self.logger.info(f"    {preview}")

            internaldate_str, message_bytes, flags_str = self.parse_fetch_response(data)

            if not message_bytes:
                return False, "Failed to parse message"

            if not internaldate_str:
                return False, "No INTERNALDATE in response"

            # Parse internal date
            try:
                internal_date = self.parse_internaldate(internaldate_str)
            except Exception as e:
                return False, f"Failed to parse INTERNALDATE '{internaldate_str}': {e}"

            # Parse email Date header
            msg = email.message_from_bytes(message_bytes)
            date_header = msg.get('Date')

            if not date_header:
                return False, "No Date header"

            try:
                parsed_date = email.utils.parsedate_to_datetime(date_header)
            except Exception as e:
                return False, f"Failed to parse Date header: {e}"

            # Ensure timezone-aware datetime
            # Some emails have Date headers without timezone info
            if parsed_date.tzinfo is None:
                self.logger.debug(f"  UID {uid.decode()}: Date header has no timezone, assuming UTC")
                parsed_date = parsed_date.replace(tzinfo=timezone.utc)

            # Compare dates
            if self.dates_match(internal_date, parsed_date):
                return True, "Already matching"

            # Prepare for update
            formatted_date = self.format_imap_date(parsed_date)
            normalized_flags = self.normalize_flags(flags_str)

            if self.dry_run:
                self.logger.info(f"  Would update UID {uid.decode()}: {internaldate_str} -> {formatted_date}")
                return True, "Would update"

            # Actually update: APPEND then DELETE
            # Build APPEND command
            flags_part = f"({normalized_flags})" if normalized_flags else "()"

            try:
                status, response = self.imap.append(
                    mailbox,
                    flags_part,
                    formatted_date,
                    message_bytes
                )

                if status != 'OK':
                    return False, f"APPEND failed: {status} - {response}"

                # APPEND succeeded, now delete original
                status, response = self.imap.uid('store', uid, '+FLAGS', '(\\Deleted)')
                if status != 'OK':
                    self.logger.warning(f"  Failed to mark UID {uid.decode()} as deleted: {status}")
                    return False, f"DELETE failed: {status}"

                self.logger.info(f"  Updated UID {uid.decode()}: {internaldate_str} -> {formatted_date}")
                return True, "Updated"

            except Exception as e:
                return False, f"Update failed: {e}"

        except Exception as e:
            return False, f"Unexpected error: {e}"

    def get_all_uids_batched(self, total_messages: int, batch_size: int = 10000) -> List[bytes]:
        """Get all UIDs in batches to avoid buffer overflow.

        Args:
            total_messages: Total number of messages in the mailbox
            batch_size: Number of messages to fetch UIDs for in each batch

        Returns:
            List of all UIDs as bytes
        """
        all_uids = []

        # Fetch UIDs in batches using message sequence number (MSN) ranges
        num_batches = (total_messages + batch_size - 1) // batch_size
        self.logger.info(f"  Fetching UIDs in {num_batches} batches of up to {batch_size} messages...")

        for batch_num in range(num_batches):
            start = batch_num * batch_size + 1
            end = min((batch_num + 1) * batch_size, total_messages)

            self.logger.debug(f"  Batch {batch_num + 1}/{num_batches}: messages {start}:{end}")

            # Fetch UIDs for this range of message sequence numbers
            # We use FETCH to get the UID for each message in the range
            status, data = self.imap.fetch(f'{start}:{end}'.encode(), '(UID)')

            if status == 'OK':
                # Parse UIDs from FETCH response
                # Format: [b'1 (UID 12345)', b'2 (UID 12346)', ...]
                for response in data:
                    if isinstance(response, bytes):
                        match = re.search(rb'UID (\d+)', response)
                        if match:
                            all_uids.append(match.group(1))
                    elif isinstance(response, tuple) and len(response) > 0:
                        match = re.search(rb'UID (\d+)', response[0])
                        if match:
                            all_uids.append(match.group(1))

                batch_count = sum(1 for resp in data if isinstance(resp, (bytes, tuple)))
                self.logger.debug(f"    Retrieved {batch_count} UIDs from this batch")

        return all_uids

    def process_mailbox(self, mailbox: str) -> MessageStats:
        """Process all messages in a mailbox."""
        stats = MessageStats()

        self.logger.info(f"\nProcessing mailbox: {mailbox}")

        try:
            # Select mailbox in read-write mode
            status, data = self.imap.select(mailbox)
            if status != 'OK':
                self.logger.error(f"Failed to select mailbox {mailbox}: {status}")
                return stats

            message_count = int(data[0])
            self.logger.info(f"  Messages: {message_count}")

            if message_count == 0:
                return stats

            # Get all UIDs in batches to avoid buffer overflow
            uids = self.get_all_uids_batched(message_count)

            if not uids:
                self.logger.error(f"Failed to fetch UIDs")
                return stats

            stats.total = len(uids)
            self.logger.info(f"  Retrieved {stats.total} UIDs")

            # Process each message
            for i, uid in enumerate(uids, 1):
                if i % 100 == 0:
                    self.logger.info(f"  Progress: {i}/{stats.total}")

                success, message = self.process_message(uid, mailbox)

                if not success:
                    if "No Date header" in message:
                        stats.skipped_no_date += 1
                        self.logger.warning(f"  UID {uid.decode()}: {message}")
                    else:
                        stats.skipped_error += 1
                        self.logger.error(f"  UID {uid.decode()}: {message}")
                elif "Already matching" in message:
                    stats.skipped_matching += 1
                elif "Would update" in message:
                    stats.would_update += 1
                elif "Updated" in message:
                    stats.updated += 1

            # Expunge deleted messages (only if not dry-run)
            if not self.dry_run and stats.updated > 0:
                self.logger.info("  Expunging deleted messages...")
                self.imap.expunge()

        except Exception as e:
            self.logger.error(f"Error processing mailbox {mailbox}: {e}")

        return stats

    def process_mailboxes(self, mailboxes: List[str]) -> None:
        """Process multiple mailboxes."""
        total_stats = MessageStats()

        for mailbox in mailboxes:
            stats = self.process_mailbox(mailbox)
            total_stats.total += stats.total
            total_stats.skipped_no_date += stats.skipped_no_date
            total_stats.skipped_matching += stats.skipped_matching
            total_stats.skipped_error += stats.skipped_error
            total_stats.updated += stats.updated
            total_stats.would_update += stats.would_update

        # Print summary
        self.logger.info("\n" + "="*60)
        self.logger.info("SUMMARY")
        self.logger.info("="*60)
        self.logger.info(f"Total messages:           {total_stats.total}")
        self.logger.info(f"Already matching:         {total_stats.skipped_matching}")
        self.logger.info(f"Missing Date header:      {total_stats.skipped_no_date}")
        self.logger.info(f"Errors:                   {total_stats.skipped_error}")

        if self.dry_run:
            self.logger.info(f"Would update:             {total_stats.would_update}")
            self.logger.info("\nDRY RUN - No changes were made")
            self.logger.info("Run with --execute to apply changes")
        else:
            self.logger.info(f"Updated:                  {total_stats.updated}")


def main():
    parser = argparse.ArgumentParser(
        description="Reset IMAP message internal dates to match Date headers",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Network mode - Dry run (default) on INBOX
  %(prog)s --server imap.gmail.com --username user@gmail.com --mailboxes INBOX

  # Network mode - Actually update messages
  %(prog)s --server imap.gmail.com --username user@gmail.com --mailboxes INBOX --execute

  # Network mode - Process multiple mailboxes
  %(prog)s --server imap.gmail.com --username user@gmail.com --mailboxes INBOX Sent Drafts

  # Network mode - List available mailboxes
  %(prog)s --server imap.gmail.com --username user@gmail.com --list-mailboxes

  # Local process mode - Access Dovecot directly (no authentication needed)
  %(prog)s --process "/usr/local/libexec/dovecot/imap" --mailboxes INBOX

  # Local process mode - List mailboxes
  %(prog)s --process "/usr/local/libexec/dovecot/imap" --list-mailboxes

  # Local process mode - Actually update (must run as mail user)
  sudo -u vmail %(prog)s --process "/usr/local/libexec/dovecot/imap" --mailboxes INBOX --execute
        """
    )

    parser.add_argument('--server', help='IMAP server hostname (network mode)')
    parser.add_argument('--port', type=int, default=993, help='IMAP server port (default: 993)')
    parser.add_argument('--username', help='IMAP username (network mode)')
    parser.add_argument('--password', help='IMAP password (network mode, will prompt if not provided)')
    parser.add_argument('--password-file', help='File containing password (network mode)')
    parser.add_argument('--process', '-P', help='IMAP process to spawn for local access (e.g., /usr/local/libexec/dovecot/imap)')
    parser.add_argument('--mailboxes', nargs='+', help='Mailbox names to process')
    parser.add_argument('--list-mailboxes', action='store_true', help='List available mailboxes and exit')
    parser.add_argument('--execute', action='store_true', help='Actually modify messages (default is dry-run)')
    parser.add_argument('--no-skip-matching', action='store_true', help='Process even if dates already match')
    parser.add_argument('--verbose', '-v', action='store_true', help='Verbose logging')
    parser.add_argument('--debug-fetch', action='store_true', help='Show raw FETCH responses for debugging')

    args = parser.parse_args()

    # Setup logging
    log_level = logging.DEBUG if args.verbose else logging.INFO
    logging.basicConfig(
        level=log_level,
        format='%(levelname)s: %(message)s'
    )
    logger = logging.getLogger(__name__)

    # Validate mode selection
    if args.process:
        # Local process mode - server/username/password not required
        if args.server or args.username or args.password or args.password_file:
            logger.warning("Warning: --server, --username, and --password are ignored when using --process")
        password = None
    else:
        # Network mode - server and username required
        if not args.server:
            logger.error("Error: --server is required (or use --process for local mode)")
            return 1
        if not args.username:
            logger.error("Error: --username is required (or use --process for local mode)")
            return 1

        # Get password for network mode
        password = args.password
        if args.password_file:
            with open(args.password_file) as f:
                password = f.read().strip()
        if not password:
            import getpass
            password = getpass.getpass(f"Password for {args.username}: ")

    # Create synchronizer
    dry_run = not args.execute
    skip_matching = not args.no_skip_matching

    sync = IMAPDateSynchronizer(
        server=args.server,
        port=args.port,
        username=args.username,
        password=password,
        process=args.process,
        dry_run=dry_run,
        skip_matching=skip_matching
    )
    sync.debug_fetch = args.debug_fetch

    try:
        sync.connect()

        # List mailboxes if requested
        if args.list_mailboxes:
            mailboxes = sync.list_mailboxes()
            logger.info("Available mailboxes:")
            for mb in mailboxes:
                logger.info(f"  {mb}")
            return 0

        # Validate mailboxes argument
        if not args.mailboxes:
            logger.error("Error: --mailboxes required (or use --list-mailboxes)")
            return 1

        if dry_run:
            logger.info("="*60)
            logger.info("DRY RUN MODE - No changes will be made")
            logger.info("="*60)

        # Process mailboxes
        sync.process_mailboxes(args.mailboxes)

        return 0

    except Exception as e:
        logger.error(f"Fatal error: {e}")
        import traceback
        traceback.print_exc()
        return 1

    finally:
        sync.disconnect()


if __name__ == '__main__':
    sys.exit(main())
