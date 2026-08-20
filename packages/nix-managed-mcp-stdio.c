#define _POSIX_C_SOURCE 200809L

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef NIX_MANAGED_MCP_PATH
#error "NIX_MANAGED_MCP_PATH must name the immutable managed runtime PATH"
#endif

extern char **environ;

static const char managed_path[] = "PATH=" NIX_MANAGED_MCP_PATH;

static int valid_name(const char *name) {
  const unsigned char *cursor = (const unsigned char *)name;

  if (*cursor < 'A' || *cursor > 'Z') {
    return 0;
  }
  for (++cursor; *cursor != '\0'; ++cursor) {
    if ((*cursor < 'A' || *cursor > 'Z') && (*cursor < '0' || *cursor > '9') &&
        *cursor != '_') {
      return 0;
    }
  }
  return 1;
}

static int name_allowed(const char *entry, size_t length, char **names,
                        size_t name_count) {
  size_t index;

  for (index = 0; index < name_count; ++index) {
    if (strlen(names[index]) == length &&
        memcmp(entry, names[index], length) == 0) {
      return 1;
    }
  }
  return 0;
}

static int unresolved_reference(const char *entry, const char *separator) {
  const char *value = separator + 1;
  size_t name_length = (size_t)(separator - entry);
  size_t value_length = strlen(value);

  if ((value_length != name_length + 3 && value_length != name_length + 5) ||
      value[0] != '$' || value[1] != '{' ||
      memcmp(value + 2, entry, name_length) != 0) {
    return 0;
  }
  return (value_length == name_length + 3 && value[name_length + 2] == '}') ||
         (value[name_length + 2] == ':' && value[name_length + 3] == '-' &&
          value[name_length + 4] == '}');
}

static int close_from_directory(const char *path) {
  DIR *directory = opendir(path);
  struct dirent *item;
  int directory_descriptor;

  if (directory == NULL) {
    return 1;
  }
  directory_descriptor = dirfd(directory);
  if (directory_descriptor < 0) {
    (void)closedir(directory);
    return -1;
  }

  for (;;) {
    char *end;
    long descriptor;

    errno = 0;
    item = readdir(directory);
    if (item == NULL) {
      if (errno != 0) {
        (void)closedir(directory);
        return -1;
      }
      break;
    }
    if (item->d_name[0] < '0' || item->d_name[0] > '9') {
      continue;
    }
    errno = 0;
    descriptor = strtol(item->d_name, &end, 10);
    if (errno != 0 || *end != '\0' || descriptor > INT_MAX) {
      (void)closedir(directory);
      return -1;
    }
    if (descriptor < 3 || descriptor == directory_descriptor) {
      continue;
    }
    while (close((int)descriptor) < 0) {
      if (errno == EINTR) {
        continue;
      }
      if (errno != EBADF) {
        (void)closedir(directory);
        return -1;
      }
      break;
    }
  }
  if (closedir(directory) < 0) {
    return -1;
  }
  return 0;
}

static int close_extra_descriptors(void) {
  const char *directories[] = {"/proc/self/fd", "/dev/fd"};
  size_t index;
  long maximum;
  int descriptor;

  for (index = 0; index < sizeof(directories) / sizeof(directories[0]);
       ++index) {
    int result = close_from_directory(directories[index]);

    if (result <= 0) {
      return result;
    }
  }

  maximum = sysconf(_SC_OPEN_MAX);
  if (maximum < 0 || maximum > INT_MAX) {
    return -1;
  }
  for (descriptor = 3; descriptor < maximum; ++descriptor) {
    while (close(descriptor) < 0) {
      if (errno == EINTR) {
        continue;
      }
      if (errno != EBADF) {
        return -1;
      }
      break;
    }
  }
  return 0;
}

static int usage(const char *message) {
  fprintf(stderr, "nix-managed-mcp-stdio: %s\n", message);
  return 64;
}

int main(int argc, char **argv) {
  char **allowed_names;
  char **filtered_environment;
  size_t allowed_count = 0;
  size_t environment_count = 0;
  size_t filtered_count = 0;
  int argument = 1;
  int target;
  int saved_errno;
  char **entry;

  allowed_names = calloc((size_t)argc, sizeof(*allowed_names));
  if (allowed_names == NULL) {
    perror("nix-managed-mcp-stdio: calloc");
    return 70;
  }

  while (argument < argc && strcmp(argv[argument], "--inherit") == 0) {
    if (argument + 1 >= argc) {
      return usage("--inherit requires a variable name");
    }
    if (!valid_name(argv[argument + 1])) {
      return usage("invalid environment variable name");
    }
    if (strcmp(argv[argument + 1], "PATH") == 0) {
      return usage("PATH is managed internally");
    }
    if (name_allowed(argv[argument + 1], strlen(argv[argument + 1]),
                     allowed_names, allowed_count)) {
      return usage("duplicate environment variable name");
    }
    allowed_names[allowed_count++] = argv[argument + 1];
    argument += 2;
  }

  if (argument >= argc || strcmp(argv[argument], "--") != 0) {
    return usage("missing -- before the target command");
  }
  target = ++argument;
  if (target >= argc) {
    return usage("missing target command");
  }

  if (argv[target][0] != '/') {
    return usage("target command must be absolute");
  }

  for (entry = environ; *entry != NULL; ++entry) {
    ++environment_count;
  }
  filtered_environment =
      calloc(environment_count + 2, sizeof(*filtered_environment));
  if (filtered_environment == NULL) {
    perror("nix-managed-mcp-stdio: calloc");
    return 70;
  }

  for (entry = environ; *entry != NULL; ++entry) {
    const char *separator = strchr(*entry, '=');

    if (separator != NULL &&
        name_allowed(*entry, (size_t)(separator - *entry), allowed_names,
                     allowed_count) &&
        /* Client renderers normalize an absent optional value to empty. */
        separator[1] != '\0' &&
        !unresolved_reference(*entry, separator)) {
      filtered_environment[filtered_count++] = *entry;
    }
  }
  filtered_environment[filtered_count++] = (char *)managed_path;
  filtered_environment[filtered_count] = NULL;
  if (close_extra_descriptors() < 0) {
    fputs("nix-managed-mcp-stdio: could not close inherited descriptors\n",
          stderr);
    return 70;
  }
  execve(argv[target], &argv[target], filtered_environment);
  saved_errno = errno;
  fprintf(stderr, "nix-managed-mcp-stdio: could not execute target: %s\n",
          strerror(saved_errno));
  return saved_errno == ENOENT ? 127 : 126;
}
