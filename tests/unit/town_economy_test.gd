extends "res://tests/test_case.gd"

func _world() -> Array:
	var population := TownPopulation.new()
	population.ensure_population(1)
	var economy := TownEconomy.new()
	economy.ensure_households(population, 480)
	return [population, economy]

func _coins(economy: TownEconomy) -> int:
	var total: int = economy.treasury
	for coins: int in economy.accounts.values():
		total += coins
	return total

func test_settlement_with_a_missing_input_stock_neither_errors_nor_creates_coins() -> void:
	var world: Array = _world()
	var population: TownPopulation = world[0]
	var economy: TownEconomy = world[1]
	var total: int = _coins(economy)
	economy.stock.erase("grain")
	economy.stock.erase("flour")
	for id: String in population.people:
		economy.record_work(id, 480)
	economy.settle(1440, population, [])
	assert_eq(_coins(economy), total)
	assert_false(economy.stock.has("grain"), "an untracked good is not invented")
	for coins: int in economy.accounts.values():
		assert_true(coins >= 0)

func test_settlement_with_no_food_stock_records_shortages() -> void:
	var world: Array = _world()
	var population: TownPopulation = world[0]
	var economy: TownEconomy = world[1]
	economy.stock.erase("food")
	economy.settle(1440, population, [])
	assert_false(economy.shortages.is_empty())
	assert_false(economy.stock.has("food"))

func test_only_recorded_work_is_paid_and_pay_is_not_repeated() -> void:
	var world: Array = _world()
	var population: TownPopulation = world[0]
	var economy: TownEconomy = world[1]
	economy.record_work("holt_child_a", 600)
	economy.settle(1440, population, [])
	assert_false(economy.ledger.any(func(entry: Dictionary) -> bool:
		return entry.kind == "income" and entry.household == population.household_for("holt_child_a") and entry.coins > 0),
		"children are never paid")
	economy.record_work("rowan_father", 480)
	economy.settle(1440, population, [])
	assert_true(economy.work_minutes.has("rowan_father"), "the same day settles once")
