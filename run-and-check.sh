#!/usr/bin/env bash
#
# Launches the plugdata standalone, which (when built with -DENABLE_TESTING=1)
# automatically runs the end-to-end test suite at startup and quits when done.
#
# The app's exit code does not reflect unit-test assertion failures, so we
# capture stdout/stderr and fail the job if:
#   - a sanitizer (ASAN/UBSan/LSan) reports an error,
#   - the JUCE UnitTestRunner prints a failure ("!!! Test N failed" / "FAILED!!"),
#   - the run times out or the app crashes,
#   - or the suite never started (build/run misconfiguration).
#
# Must be run from the workspace root (the directory containing ./plugdata).
set -u

LOG="test-output.log"

case "$(uname -s)" in
    Darwin) APP="plugdata/Plugins/Standalone/plugdata.app/Contents/MacOS/plugdata"; RUNNER="" ;;
    Linux)  APP="plugdata/Plugins/Standalone/plugdata";                              RUNNER="xvfb-run -a" ;;
    *)      APP="plugdata/Plugins/Standalone/plugdata.exe";                          RUNNER="" ;; # MINGW/MSYS (Windows)
esac

if [ ! -e "$APP" ]; then
    echo "::error::Standalone binary not found at $APP"
    echo "Contents of plugdata/Plugins/Standalone:"
    ls -la plugdata/Plugins/Standalone 2>/dev/null || true
    exit 1
fi

# Leak detection is noisy at app shutdown (singletons etc.); we care about
# use-after-free / overflows here, so turn LSan off but keep ASAN hard-failing.
export ASAN_OPTIONS="detect_leaks=0:abort_on_error=1:print_stats=0"
export UBSAN_OPTIONS="print_stacktrace=1:halt_on_error=0"

# Use a hard timeout if available so a hang doesn't burn the whole job budget.
TIMEOUT=""
if command -v timeout >/dev/null 2>&1; then TIMEOUT="timeout 14400"; fi

echo "Running: $RUNNER $TIMEOUT $APP"
echo "===================== test output (live) ====================="
set +e
# Stream output to the Actions console live while still capturing the full log
# for the grep checks below and the artifact upload. tee would otherwise mask
# the app's exit code, so we read it back from PIPESTATUS[0] (the app/timeout,
# not tee).
$RUNNER $TIMEOUT "$APP" 2>&1 | tee "$LOG"
code=${PIPESTATUS[0]}
echo "===================== exit code: $code ====================="

fail=0

if [ "$code" = "124" ]; then
    echo "::error::Test run timed out"
    fail=1
fi

if grep -qiE "AddressSanitizer|LeakSanitizer|ThreadSanitizer|runtime error:|heap-buffer-overflow|heap-use-after-free|stack-buffer-overflow|SUMMARY: .*Sanitizer" "$LOG"; then
    echo "::error::Sanitizer reported an error (see log)"
    fail=1
fi

if grep -qE "!!! Test [0-9]+ failed|FAILED!!" "$LOG"; then
    echo "::error::Unit-test failure(s) detected"
    fail=1
fi

if ! grep -q "Starting tests in:" "$LOG"; then
    echo "::error::Test suite did not start - is the runner enabled in Tests.cpp on this branch?"
    fail=1
fi

# Any other non-zero, non-timeout exit is a crash we didn't otherwise classify.
if [ "$fail" = "0" ] && [ "$code" != "0" ]; then
    echo "::error::App exited abnormally (code $code)"
    fail=1
fi

if [ "$fail" = "0" ]; then
    echo "✅ All tests passed"
fi

exit "$fail"
