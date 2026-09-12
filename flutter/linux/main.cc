#include <dlfcn.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "my_application.h"

#define RUSTDESK_LIB_PATH "librustdesk.so"
typedef bool (*RustDeskCoreMain)();
bool gIsConnectionManager = false;

void print_help_install_pkg(const char* so);

// The bundle keeps the core library at lib/librustdesk.so next to the
// executable. Resolve that path explicitly instead of relying on the
// runner's RPATH, which repackaged installs may strip.
// https://github.com/rustdesk/rustdesk/discussions/14407
static void* dlopen_bundled_lib() {
  char exe_path[PATH_MAX];
  ssize_t len = readlink("/proc/self/exe", exe_path, sizeof(exe_path) - 1);
  if (len <= 0 || len >= (ssize_t)(sizeof(exe_path) - 1)) return nullptr;
  exe_path[len] = '\0';
  char* last_slash = strrchr(exe_path, '/');
  if (last_slash == nullptr) return nullptr;
  *last_slash = '\0';
  char lib_path[PATH_MAX + sizeof("/lib/" RUSTDESK_LIB_PATH)];
  snprintf(lib_path, sizeof(lib_path), "%s/lib/%s", exe_path, RUSTDESK_LIB_PATH);
  if (access(lib_path, F_OK) != 0) return nullptr;
  void* librustdesk = dlopen(lib_path, RTLD_LAZY);
  if (!librustdesk) {
    char* error = dlerror();
    if (error != nullptr) {
      fprintf(stderr, "Failed to load \"%s\": %s\n", lib_path, error);
    }
  }
  return librustdesk;
}

bool flutter_rustdesk_core_main() {
   void* librustdesk = dlopen_bundled_lib();
   if (!librustdesk) {
      librustdesk = dlopen(RUSTDESK_LIB_PATH, RTLD_LAZY);
   }
   if (!librustdesk) {
      fprintf(stderr,"Failed to load \"librustdesk.so\"\n");
      char* error;
      if ((error = dlerror()) != nullptr) {
        fprintf(stderr, "%s\n", error);
        char* libmissed = strstr(error, ": cannot open shared object file: No such file or directory");
        if (libmissed != nullptr) {
          *libmissed = '\0';
          char* so = strdup(error);
          print_help_install_pkg(so);
          free(so);
        }
      }
     return false;
   }
   auto core_main = (RustDeskCoreMain) dlsym(librustdesk,"rustdesk_core_main");
   char* error;
   if ((error = dlerror()) != nullptr) {
       fprintf(stderr, "Program entry \"rustdesk_core_main\" is not found: %s\n", error);
       return false;
   }
   return core_main();
}

int main(int argc, char** argv) {
  // REVERTED (2026-09-12): forcing GDK_BACKEND=x11,wayland here made
  // xdotool able to find and activate the window (verified), but also
  // crashed the --server process outright on architect immediately after
  // startup, inside GTK itself:
  //   Got signal 11 and exit. stack:
  //   gtk_window_is_maximized
  //   _ZL14method_call_cbP16_FlMethodChannelP13_FlMethodCallPv
  //   g_main_context_iteration / g_application_run / main
  // i.e. a segfault inside GTK's own maximized-state query, reached via the
  // window_manager plugin's method channel, applying to every role that
  // runs through this main() (including headless --server, which still
  // spins up a GTK application loop) -- not just the user-facing main
  // window this was meant to help. A crash that breaks incoming
  // connections entirely ("No Displays") is far worse than the slow tray
  // activation this was fixing, so it's reverted rather than scoped down:
  // scoping it to skip --server etc. wouldn't rule out the same crash
  // recurring intermittently in the main window's own GTK init (this one
  // didn't reproduce on every run either). The KDE/KWin tray-activation fix
  // in src/server/dbus.rs's activate_via_kwin_script() and
  // flutter/lib/common.dart's _activateViaKWinScript() does not depend on
  // this and is unaffected by the revert. GNOME/Mutter tray activation
  // returns to its prior (slow/no-op) behavior until a safe way to make
  // the window visible to xdotool is found.
  if (!flutter_rustdesk_core_main()) {
      return 0;
  }
  for (int i = 0; i < argc; i++) {
    if (strcmp(argv[i], "--cm") == 0) {
      gIsConnectionManager = true;
    }
  }
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}

typedef struct {
  const char* mgr;
  const char* search;
} PkgMgrSearch;

const PkgMgrSearch g_mgrs[] = {
  {
    "apt",
    "apt-file search",
  },
  {
    "dnf",
    "dnf provides",
  },
  {
    "yum",
    "yum provides",
  },
  {
    "zypper",
    "zypper wp",
  },
  {
    "pacman",
    "pacman -Qo",
  },
  {
    NULL,
    NULL,
  },
};

int is_command_exists(const char* command) {
    char* path = getenv("PATH");
    char* path_copy = strdup(path);
    char* dir = strtok(path_copy, ":");

    while (dir != NULL) {
        char command_path[256];
        snprintf(command_path, sizeof(command_path), "%s/%s", dir, command);
        if (access(command_path, X_OK) == 0) {
            free(path_copy);
            return 1;
        }
        dir = strtok(NULL, ":");
    }

    free(path_copy);
    return 0;
}

// We do not automatically search pkg 
// as the search process can be time consuming and update may be required.
void print_help_install_pkg(const char* so)
{
  if (strcmp(so, "libnsl.so.1") == 0) {
    const char* mgr[] = {"yum", "dnf", NULL};
    const char** m = mgr;
    while (*m != NULL) {
      if (is_command_exists(*m)) {
        fprintf(stderr, "Please run \"%s install libnsl\" to install the required package.\n", *m);
        return;
      }
      m++;
    }
  }

  const PkgMgrSearch *mgr_search = g_mgrs;
  while (mgr_search->mgr != NULL) {
      if (is_command_exists(mgr_search->mgr) == 1) {
        fprintf(stderr, "Please run \"%s %s\" to search and install the pkg.\n", mgr_search->search, so);
        break;
      }
      mgr_search++;
  }
}
