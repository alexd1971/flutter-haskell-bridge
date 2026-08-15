#include <HsFFI.h>
#include <pthread.h>

static pthread_once_t haskell_runtime_once = PTHREAD_ONCE_INIT;

static void initialize_haskell_runtime(void) {
  int argc = 1;
  char *argv[] = { "flutter-haskell-bridge", NULL };
  char **argv_ptr = argv;
  hs_init(&argc, &argv_ptr);
}

void haskell_init(void) {
  pthread_once(&haskell_runtime_once, initialize_haskell_runtime);
}
