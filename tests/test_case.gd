class_name TestCase
extends RefCounted

var _failures: Array[String] = []

func before_each() -> void:
	pass

func after_each() -> void:
	pass

func assert_true(value: bool, message: String = "Expected value to be true.") -> void:
	if not value:
		_fail(message)

func assert_false(value: bool, message: String = "Expected value to be false.") -> void:
	if value:
		_fail(message)

func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if actual != expected:
		var failure_message := message
		if failure_message.is_empty():
			failure_message = "Expected %s, got %s." % [str(expected), str(actual)]
		_fail(failure_message)

func assert_ne(actual: Variant, expected: Variant, message: String = "") -> void:
	if actual == expected:
		var failure_message := message
		if failure_message.is_empty():
			failure_message = "Expected value to differ from %s." % [str(expected)]
		_fail(failure_message)

func assert_null(value: Variant, message: String = "Expected value to be null.") -> void:
	if value != null:
		_fail(message)

func assert_not_null(value: Variant, message: String = "Expected value not to be null.") -> void:
	if value == null:
		_fail(message)

func get_failures() -> Array[String]:
	return _failures.duplicate()

func clear_failures() -> void:
	_failures.clear()

func _fail(message: String) -> void:
	_failures.append(message)
