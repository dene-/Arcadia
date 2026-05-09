extends SceneTree

const TEST_ROOT := "res://tests/unit"
const TEST_FILE_SUFFIX := "_test.gd"
const TEST_METHOD_PREFIX := "test_"

var _test_count: int = 0
var _failure_count: int = 0

func _initialize() -> void:
	var test_files := _discover_tests(TEST_ROOT)
	test_files.sort()

	if test_files.is_empty():
		push_error("No Godot tests found in %s." % TEST_ROOT)
		quit(1)
		return

	for test_file: String in test_files:
		_run_test_file(test_file)

	print("")
	if _failure_count == 0:
		print("Godot tests passed: %d" % _test_count)
		quit(0)
	else:
		push_error("Godot tests failed: %d of %d" % [_failure_count, _test_count])
		quit(1)

func _discover_tests(root_path: String) -> PackedStringArray:
	var results := PackedStringArray()
	var dir := DirAccess.open(root_path)
	if dir == null:
		return results

	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while not entry_name.is_empty():
		if entry_name.begins_with("."):
			entry_name = dir.get_next()
			continue

		var entry_path := "%s/%s" % [root_path, entry_name]
		if dir.current_is_dir():
			results.append_array(_discover_tests(entry_path))
		elif entry_name.ends_with(TEST_FILE_SUFFIX):
			results.append(entry_path)
		entry_name = dir.get_next()

	return results

func _run_test_file(test_file: String) -> void:
	var test_script := load(test_file) as GDScript
	if test_script == null:
		_record_failure(test_file, "<load>", "Could not load test script.")
		return
	if not test_script.can_instantiate():
		_record_failure(test_file, "<load>", "Test script could not be instantiated.")
		return

	var test_case: Object = test_script.new()
	if not _is_valid_test_case(test_case):
		_record_failure(test_file, "<init>", "Test script must extend res://tests/test_case.gd.")
		return

	var test_methods := _get_test_methods(test_case)
	if test_methods.is_empty():
		_record_failure(test_file, "<discover>", "No test_* methods found.")
		return

	print("Running %s" % test_file)
	for method_name: StringName in test_methods:
		_run_test_method(test_file, test_case, method_name)

func _is_valid_test_case(test_case: Variant) -> bool:
	return (
		test_case != null
		and test_case.has_method("before_each")
		and test_case.has_method("after_each")
		and test_case.has_method("clear_failures")
		and test_case.has_method("get_failures")
	)

func _get_test_methods(test_case: Object) -> Array[StringName]:
	var test_methods: Array[StringName] = []
	for method_data: Dictionary in test_case.get_method_list():
		var method_name := method_data["name"] as StringName
		if String(method_name).begins_with(TEST_METHOD_PREFIX):
			test_methods.append(method_name)
	test_methods.sort()
	return test_methods

func _run_test_method(test_file: String, test_case: Object, method_name: StringName) -> void:
	_test_count += 1
	test_case.clear_failures()
	test_case.before_each()
	test_case.call(method_name)
	test_case.after_each()

	var failures: Array = test_case.get_failures()
	if failures.is_empty():
		print("  PASS %s" % method_name)
		return

	for failure: String in failures:
		_record_failure(test_file, String(method_name), failure)

func _record_failure(test_file: String, method_name: String, message: String) -> void:
	_failure_count += 1
	push_error("  FAIL %s %s: %s" % [test_file, method_name, message])
