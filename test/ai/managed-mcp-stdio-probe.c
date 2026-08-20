#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int present_with_value(const char *name, const char *expected) {
  const char *value = getenv(name);
  return value != NULL && strcmp(value, expected) == 0;
}

static int absent(const char *name) { return getenv(name) == NULL; }

int main(int argc, char **argv) {
  char input[64];
  char cwd[4096];
  const char *forbidden[] = {
      "BASH_ENV",       "DYLD_INSERT_LIBRARIES", "GEMINI_API_KEY",
      "GIT_AI_SOCKET",  "GIT_TRACE2_EVENT",     "LD_PRELOAD",
      "NODE_OPTIONS",   "PYTHONPATH",            "SSH_AUTH_SOCK",
      "UNRELATED_SECRET",
  };
  size_t index;

  if (argc == 2 && strcmp(argv[1], "exit") == 0) {
    return 23;
  }
  if (argc == 2 && strcmp(argv[1], "signal") == 0) {
    if (signal(SIGTERM, SIG_DFL) == SIG_ERR || raise(SIGTERM) != 0) {
      return 71;
    }
    return 70;
  }
  if (argc == 2 && strcmp(argv[1], "fd") == 0) {
    errno = 0;
    if (fcntl(9, F_GETFD) >= 0 || errno != EBADF) {
      return 18;
    }
    return fputs("ok\n", stdout) == EOF ? 19 : 0;
  }
  if (argc != 5 || strcmp(argv[2], "argument-sentinel") != 0 ||
      getcwd(cwd, sizeof(cwd)) == NULL || strcmp(cwd, argv[3]) != 0) {
    return 10;
  }
  if (!present_with_value("HOME", "/managed-home") ||
      !present_with_value("PATH", argv[4]) ||
      !present_with_value("DEFAULT_MODEL", "auto")) {
    return 11;
  }
  if (strcmp(argv[1], "present") == 0) {
    if (!present_with_value("OPENAI_API_KEY", "typed-sentinel") ||
        !present_with_value("ANTHROPIC_API_KEY", "anthropic-sentinel") ||
        !present_with_value("NODE_EXTRA_CA_CERTS", "/managed-node-ca")) {
      return 12;
    }
  } else if (strcmp(argv[1], "absent") == 0) {
    if (!absent("OPENAI_API_KEY") || !absent("ANTHROPIC_API_KEY") ||
        !absent("NODE_EXTRA_CA_CERTS")) {
      return 13;
    }
  } else {
    return 14;
  }
  for (index = 0; index < sizeof(forbidden) / sizeof(forbidden[0]); ++index) {
    if (!absent(forbidden[index])) {
      return 15;
    }
  }
  if (fgets(input, sizeof(input), stdin) == NULL ||
      strcmp(input, "input-sentinel\n") != 0) {
    return 16;
  }
  if (fputs("ok\n", stdout) == EOF) {
    return 17;
  }
  return 0;
}
