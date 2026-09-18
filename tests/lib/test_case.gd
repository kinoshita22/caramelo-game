extends RefCounted
## Base class for tests run by tests/run_tests.gd. Each test_* method runs on
## a fresh instance; failed checks are collected, not thrown.

var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [message, expected, actual])


## Passes when some error contains the fragment.
func check_error(errors: Array, fragment: String) -> void:
	for e in errors:
		if fragment in e:
			return
	failures.append("expected an error containing '%s', got %s" % [fragment, errors])


func check_no_errors(errors: Array, context: String) -> void:
	if not errors.is_empty():
		failures.append("%s: unexpected errors %s" % [context, errors])
