{ hostname, home, pkgs, ...}:
{
  enable = true;
  package = null;               # firefox is installed using homebrew

  betterfox = {
    enable = true;
    # version = "128.0"; # defaults to main branch
  };

  policies = {
		AppAutoUpdate = false;
		BackgroundAppUpdate = false;

		DisableBuiltinPDFViewer = true;
		DisableFirefoxStudies = true;
		DisableFirefoxAccounts = false;
		DisableFirefoxScreenshots = true;
		DisableForgetButton = true;
		DisableMasterPasswordCreation = true;
		DisableProfileImport = true;
		DisableProfileRefresh = true;
		DisableSetDesktopBackground = true;
		DisplayMenuBar = "default-off";
    DisplayBookmarksToolbar = "default-off";
		DisablePocket = true;
		DisableTelemetry = true;
		DisableFormHistory = true;
		DisablePasswordReveal = true;
		DontCheckDefaultBrowser = true;

    OfferToSaveLogins = false;
    EnableTrackingProtection = {
      Value =  true;
      Locked = true;
      Cryptomining = true;
      Fingerprinting = true;
      EmailTracking = true;
    };
    DefaultDownloadDirectory = "${home}/Downloads";
    OverrideFirstRunPage = "";
    OverridePostUpdatePage = "";
    ExtensionUpdate = false;
    SearchBar = "unified";

    FirefoxSuggest = {
			WebSuggestions = false;
			SponsoredSuggestions = false;
			ImproveSuggest = false;
			Locked = true;
    };

    Handlers = {
			mimeTypes."application/pdf".action = "saveToDisk";
		};
    PasswordManagerEnabled = false;
    PromptForDownloadLocation = false;

    SanitizeOnShutdown = {
			Cache = true;
			Cookies = true;
			Downloads = true;
			FormData = true;
			History = false;
			Sessions = false;
			SiteSettings = false;
			OfflineApps = true;
			Locked = true;
		};

    SearchEngines = {
			PreventInstalls = true;
			Add = [
				{
					Name = "Kagi";
					URLTemplate = "https://kagi.com/search?q={searchTerms}";
					Method = "GET";
					IconURL = "https://kagi.com/asset/405c65f/favicon-32x32.png?v=49886a9a8f55fd41f83a89558e334f673f9e25cf";
					Description = "Kagi Search";
				}
			];
			Remove = [
				"Bing"
			];
			Default = "Kagi";
		};
		SearchSuggestEnabled = false;
  };

  profiles = pkgs.lib.optionalAttrs (hostname == "hera") {
    "3xz6u5ly.default-release" = {
      id = 0;
      name = "default-release";
      isDefault = true;
      betterfox.enable = false;
    };

    "3ltwg757.default" = {
      id = 1;
      name = "default";
      betterfox.enable = false;
    };
  } // pkgs.lib.optionalAttrs (hostname == "clio") {
    "unj6oien.default-release" = {
      id = 0;
      name = "default-release";
      isDefault = true;
      betterfox.enable = false;
    };

    "v7m0m1sc.default" = {
      id = 1;
      name = "default";
      betterfox.enable = false;
    };
  } // {
    johnw = {
      id = 2;
      name = "John Wiegley";
      isDefault = hostname == "athena";

      betterfox = {
        enable = true;
        enableAllSections = true;
      };

      extraConfig = ''
        # These two are required for the extensions mentioned below to be
        # enabled.
        user_pref("extensions.autoDisableScopes", 0);
        user_pref("extensions.enabledScopes", 15);

        user_pref("app.update.auto", false);
        user_pref("browser.engagement.sidebar-button.has-used", true);
        user_pref("browser.newtabpage.activity-stream.feeds.section.highlights", true);
        user_pref("browser.newtabpage.activity-stream.feeds.topsites", true);
        user_pref("browser.newtabpage.enabled", false);
        user_pref("browser.preferences.experimental.hidden", true);
        user_pref("browser.startup.homepage", "chrome://browser/content/blanktab.html");
        user_pref("browser.startup.page", 3);
        user_pref("browser.tabs.hoverPreview.showThumbnails", false);
        user_pref("browser.tabs.warnOnClose", true);
        user_pref("browser.toolbarbuttons.introduced.sidebar-button", true);
        user_pref("browser.toolbars.bookmarks.visibility", "never");
        user_pref("browser.urlbar.placeholderName.private", "DuckDuckGo");
        user_pref("browser.warnOnQuitShortcut", true);
        user_pref("datareporting.usage.uploadEnabled", false);
        user_pref("doh-rollout.disable-heuristics", true);
        user_pref("doh-rollout.mode", 0);
        user_pref("doh-rollout.uri", "https://mozilla.cloudflare-dns.com/dns-query");
        user_pref("dom.disable_open_during_load", false);
        user_pref("dom.security.https_only_mode", true);
        user_pref("dom.security.https_only_mode_ever_enabled", true);
        user_pref("extensions.formautofill.addresses.enabled", false);
        user_pref("extensions.formautofill.creditCards.enabled", false);
        user_pref("extensions.ui.extension.hidden", false);
        user_pref("extensions.ui.plugin.hidden", false);
        user_pref("font.name.serif.x-western", "Bookerly");
        user_pref("media.videocontrols.picture-in-picture.video-toggle.enabled", false);
        user_pref("pdfjs.enabledCache.state", false);
        user_pref("pref.downloads.disable_button.edit_actions", false);
        user_pref("privacy.clearOnShutdown_v2.browsingHistoryAndDownloads", false);
        user_pref("privacy.globalprivacycontrol.enabled", false);
        user_pref("privacy.sanitize.sanitizeOnShutdown", true);
        user_pref("services.sync.engine.prefs.modified", true);
        user_pref("sidebar.backupState", "{\"command\":\"\",\"launcherWidth\":49,\"launcherExpanded\":false,\"launcherVisible\":true}");
        user_pref("sidebar.revamp", true);
        user_pref("sidebar.verticalTabs", true);
        user_pref("signon.management.page.breach-alerts.enabled", false);
        user_pref("signon.rememberSignons", false);
      '';

      containers = {
        "Kadena" = {
          id = 2;
          color = "red";
          icon = "chill";
        };
        "Assembly" = {
          id = 6;
          color = "green";
          icon = "fence";
        };
        "Copper to Gold" = {
          id = 7;
          color = "orange";
          icon = "circle";
        };
        "Banking" = {
          id = 3;
          color = "green";
          icon = "dollar";
        };
        "Shopping" = {
          id = 4;
          color = "pink";
          icon = "cart";
        };
        "Social Media" = {
          id = 9;
          color = "purple";
          icon = "fingerprint";
        };
      };

      extensions = {
        force = true;
        packages = with pkgs.nur.repos.rycee.firefox-addons; [
          onepassword-password-manager
          audiocontext-suspender
          copy-as-org-mode
          darkreader
          multi-account-containers
          history-cleaner
          old-reddit-redirect
          org-capture
          reddit-enhancement-suite
          single-file
          skip-redirect
          ublacklist
          ublock-origin
          video-downloadhelper
          vimium-c

          # Activate Reader View
          # Grammarly
          # LeechBlock NG
          # Privacy Settings
          # aria2-integration
          # augmented-steam
          # auto-tab-discard
          # bookmarks-organizer
          # choosy
          # colorzilla
          # downthemall
          # edit-with-emacs
          # font-finder
          # foxytab
          # imagus
          # native-mathml
          # open-multiple-urls
          # orbit
          # sidebery
          # simple-translate
          # stylus
          # tridactyl
          # umatrix
          # vimium
          # web-archives
          # web-developer
          # zotero-connector
        ];

        # Addon IDs can be found in about:support#addons
        settings = with pkgs.nur.repos.rycee.firefox-addons; {
          # "${auto-tab-discard.addonId}".settings = {
          #   audio = true;
          #   battery = false;
          #   click = "click.popup";
          #   faqs = false;
          #   favicon = false;
          #   favicon-delay = 500;
          #   "force.hostnames" = [];
          #   form = true;
          #   go-hidden = false;
          #   idle = true;
          #   idle-timeout = 300;
          #   "link.context" = true;
          #   log = false;
          #   "max.single.discard" = 50;
          #   memory-enabled = false;
          #   memory-value = 60;
          #   mode = "time-based";
          #   "notification.permission" = false;
          #   number = 0;
          #   online = true;
          #   "page.context" = true;
          #   paused = false;
          #   period = 600;
          #   pinned = false;
          #   prepends = "💤";
          #   simultaneous-jobs = 10;
          #   startup-pinned = true;
          #   startup-release-pinned = false;
          #   startup-unpinned = true;
          #   "tab.context" = true;
          #   "trash.period" = 24;
          #   "trash.unloaded" = false;
          #   "trash.whitelist-url" = [];
          #   whitelist = [
          #     "app.slack.com"
          #   ];
          #   whitelist-url = [];
          # };

          # "${history-cleaner.addonId}".settings = {};

          # "${single-file.addonId}".settings = {};

          "${ublock-origin.addonId}".settings = {
            userSettings = rec {
              advancedUserEnabled = true;
              cloudStorageEnabled = false;
              # collapseBlocked = false;
              uiAccentCustom = true;
              uiAccentCustom0 = "#ACA0F7";
              externalLists = pkgs.lib.concatStringsSep "\n" importedLists;
              importedLists = [
                "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/anti.piracy.txt"
                "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/doh-vpn-proxy-bypass.txt"
                "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/dyndns.txt"
                "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/fake.txt"
                "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/gambling.txt"
                "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/hoster.txt"
                "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/nsfw.txt"
                "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.mini.txt"
                "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/spam-tlds-ublock.txt"
                "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/tif.txt"
                "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/ultimate.txt"
              ];
              largeMediaSize = 250;
              # popupPanelSections = 31;
              tooltipsDisabled = true;
            };
            dynamicFilteringString = ''
              no-cosmetic-filtering: * true
              no-cosmetic-filtering: appleid.apple.com false
              no-cosmetic-filtering: bing.com false
              no-cosmetic-filtering: cnn.com false
              no-cosmetic-filtering: google.com false
              no-cosmetic-filtering: www.notion.com false
              no-cosmetic-filtering: www.notion.so false
              no-cosmetic-filtering: old.reddit.com false
              no-cosmetic-filtering: slack.com false
              no-cosmetic-filtering: kadena-io.slack.com false
              no-cosmetic-filtering: twitch.tv false
              no-cosmetic-filtering: youtube.com false
              no-csp-reports: * true
              no-large-media: * true
              no-large-media: www.amazon.com false
              no-large-media: appleid.apple.com false
              no-large-media: login.bmwusa.com false
              no-large-media: www.ftb.ca.gov false
              no-large-media: www.notion.com false
              no-large-media: www.notion.so false
              no-large-media: old.reddit.com false
              no-large-media: client.schwab.com false
              no-large-media: sws-gateway-nr.schwab.com false
              no-large-media: slack.com false
              no-large-media: kadena-io.slack.com false
              no-large-media: www.youtube.com false
              no-remote-fonts: * true
              no-remote-fonts: www.amazon.com false
              no-remote-fonts: appleid.apple.com false
              no-remote-fonts: login.bmwusa.com false
              no-remote-fonts: www.ftb.ca.gov false
              no-remote-fonts: docs.google.com false
              no-remote-fonts: drive.google.com false
              no-remote-fonts: gemini.google.com false
              no-remote-fonts: notebooklm.google.com false
              no-remote-fonts: www.google.com false
              no-remote-fonts: kadena.latticehq.com false
              no-remote-fonts: www.notion.com false
              no-remote-fonts: www.notion.so false
              no-remote-fonts: usa.onlinesrp.org false
              no-remote-fonts: old.reddit.com false
              no-remote-fonts: client.schwab.com false
              no-remote-fonts: sws-gateway-nr.schwab.com false
              no-remote-fonts: slack.com false
              no-remote-fonts: app.slack.com false
              no-remote-fonts: kadena-io.slack.com false
              no-remote-fonts: www.youtube.com false
              * * 3p-frame block
              * * 3p-script block
              * cloudflare.com * noop
              www.amazon.com * 3p noop
              www.amazon.com * 3p-frame noop
              www.amazon.com * 3p-script noop
              console.anthropic.com * 3p-frame noop
              console.anthropic.com * 3p-script noop
              appleid.apple.com * 3p-frame noop
              appleid.apple.com * 3p-script noop
              app.asana.com * 3p-frame noop
              app.asana.com * 3p-script noop
              behind-the-scene * * noop
              behind-the-scene * 1p-script noop
              behind-the-scene * 3p noop
              behind-the-scene * 3p-frame noop
              behind-the-scene * 3p-script noop
              behind-the-scene * image noop
              behind-the-scene * inline-script noop
              app01.us.bill.com * 3p-frame noop
              app01.us.bill.com * 3p-script noop
              login.bmwusa.com * 3p-frame noop
              login.bmwusa.com * 3p-script noop
              www.facebook.com * 3p noop
              www.facebook.com * 3p-frame noop
              www.facebook.com * 3p-script noop
              www.fidium.net * 3p-frame noop
              www.fidium.net * 3p-script noop
              file-scheme * 3p-frame noop
              file-scheme * 3p-script noop
              github.com * 3p noop
              github.com * 3p-frame noop
              github.com * 3p-script noop
              accounts.google.com * 3p-frame noop
              accounts.google.com * 3p-script noop
              docs.google.com * 3p-frame noop
              docs.google.com * 3p-script noop
              drive.google.com * 3p noop
              drive.google.com * 3p-frame noop
              drive.google.com * 3p-script noop
              notebooklm.google.com * 3p noop
              notebooklm.google.com * 3p-frame noop
              notebooklm.google.com * 3p-script noop
              huggingface.co * 3p-frame noop
              huggingface.co * 3p-script noop
              kadena.latticehq.com * 3p-frame noop
              kadena.latticehq.com * 3p-script noop
              www.linkedin.com * 3p noop
              www.notion.com * 3p-frame noop
              www.notion.com * 3p-script noop
              www.notion.so * 3p-frame noop
              www.notion.so * 3p-script noop
              old.reddit.com * 3p noop
              old.reddit.com * 3p-frame noop
              old.reddit.com * 3p-script noop
              www.reddit.com * 3p noop
              www.reddit.com * 3p-frame noop
              www.reddit.com * 3p-script noop
              respected-meat-54f.notion.site * 3p noop
              myprofile.saccounty.gov * 3p-frame noop
              myprofile.saccounty.gov * 3p-script noop
              myutilities.saccounty.gov * 3p-frame noop
              myutilities.saccounty.gov * 3p-script noop
              client.schwab.com * 3p-frame noop
              client.schwab.com * 3p-script noop
              sws-gateway-nr.schwab.com * 3p-frame noop
              sws-gateway-nr.schwab.com * 3p-script noop
              slack.com * 3p-frame noop
              slack.com * 3p-script noop
              app.slack.com * 3p noop
              app.slack.com * 3p-frame noop
              app.slack.com * 3p-script noop
              kadena-io.slack.com * 3p-frame noop
              kadena-io.slack.com * 3p-script noop
              www.tripit.com * 3p noop
              www.tripit.com * 3p-frame noop
              www.tripit.com * 3p-script noop
              www.usaa.com * 3p-frame noop
              www.usaa.com * 3p-script noop
              secure.verizon.com * 3p-frame noop
              secure.verizon.com * 3p-script noop
              www.verizon.com * 3p-frame noop
              www.verizon.com * 3p-script noop
              www.youtube.com * 3p-frame noop
              www.youtube.com * 3p-script noop
            '';
            urlFilteringString = "";
            hostnameSwitchesString = ''
              no-remote-fonts: * true
              no-large-media: * true
              no-csp-reports: * true
              no-remote-fonts: www.ftb.ca.gov false
              no-large-media: www.ftb.ca.gov false
              no-remote-fonts: app.slack.com false
              no-remote-fonts: notebooklm.google.com false
            '';
            userFilters = "";
            selectedFilterLists = [
              "user-filters"
              "ublock-filters"
              "ublock-badware"
              "ublock-privacy"
              "ublock-quick-fixes"
              "ublock-unbreak"
              "easylist"
              "easyprivacy"
              "adguard-spyware"
              "adguard-spyware-url"
              "urlhaus-1"
              "plowe-0"
              "fanboy-cookiemonster"
              "ublock-cookies-easylist"
              "fanboy-social"
              "easylist-chat"
              "easylist-newsletters"
              "easylist-notifications"
              "easylist-annoyances"
              "ublock-annoyances"
              "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/hoster.txt"
              "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/fake.txt"
              "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.mini.txt"
              "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/spam-tlds-ublock.txt"
            ];
            whitelist = [
              "chrome-extension-scheme"
              "moz-extension-scheme"
            ];
          };

          "${vimium-c.addonId}".settings = {
	          keyMappings = [
		          "#!no-check"
		          "map s LinkHints.activateSelect"
		          "map K previousTab"
		          "map , previousTab"
		          "map J nextTab"
		          "map . nextTab"
		          "map q LinkHints.activateWithQueue"
	          ];
	          notifyUpdate = false;
	          searchUrl = "https://kagi.com/search?q=$s Kagi";
          };
        };
      };
    };
  };
}
