#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${RECOVERY_SANITIZER_BUILD_DIR:-$project_root/build/recovery_sanitizers}"

cmake -S "$project_root/src" -B "$build_dir" \
  -DSRC_DIR="$project_root/src" \
  -DRECOVERY_ENABLE_SANITIZERS=ON \
  -DCMAKE_BUILD_TYPE=Debug
cmake --build "$build_dir" --parallel
ctest --test-dir "$build_dir" --output-on-failure

if (( $# == 0 )); then
  set -- test/recovery_test.dart
fi
case "$(uname -s)" in
  Linux)
    asan_runtime="$(cc -print-file-name=libasan.so)"
    test -f "$asan_runtime"
    # CTest above owns leak detection. Disable process-wide LSan for Flutter's
    # prebuilt runner while retaining ASan/UBSan on every recovery call.
    ASAN_OPTIONS="detect_leaks=0:halt_on_error=1:strict_string_checks=1" \
    UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1" \
    LD_PRELOAD="$asan_runtime${LD_PRELOAD:+:$LD_PRELOAD}" \
    LIBRECOVERY_PATH="$build_dir/librecovery.so" \
      flutter test "$@"
    ;;
  Darwin)
    # Apple's platform policy rejects ASan injection into Flutter's prebuilt,
    # signed test runner. CTest above still exercises the native API under both
    # sanitizers; Linux CI additionally runs the Dart FFI tests below.
    ;;
  *)
    printf 'Native recovery sanitizers are unsupported on %s.\n' "$(uname -s)" >&2
    exit 1
    ;;
esac
