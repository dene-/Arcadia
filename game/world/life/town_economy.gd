class_name TownEconomy
extends RefCounted

## Closed coin supply, household budgets and physical goods. No trading/UI dependency.
## Production requires accumulated work; settlement is once per completed game day.
const PRICES: Dictionary = {"grain": 1, "flour": 2, "food": 2, "wood": 2,
	"herbs": 2, "cloth": 3, "tools": 4, "medicine": 4, "leather": 3, "jewelry": 6}
# Output, units per four work hours, input, input units. Empty output denotes a service.
const RECIPES: Dictionary = {
	"farmer": ["grain", 24, "", 0], "farmhand": ["grain", 18, "", 0],
	"miller": ["flour", 18, "grain", 18], "baker": ["food", 24, "flour", 12],
	"cooker": ["food", 24, "flour", 12], "fisher": ["food", 14, "", 0],
	"butcher": ["food", 12, "", 0], "herb gatherer": ["herbs", 10, "", 0],
	"carpenter": ["wood", 10, "", 0], "apprentice carpenter": ["wood", 6, "", 0],
	"cooper": ["tools", 4, "wood", 4], "blacksmith": ["tools", 5, "wood", 3],
	"alchemist": ["medicine", 5, "herbs", 5], "tailor": ["cloth", 6, "", 0],
	"weaver": ["cloth", 8, "", 0], "dyer": ["cloth", 6, "herbs", 2],
	"furrier": ["leather", 6, "", 0], "leatherworker": ["leather", 5, "", 0],
	"jeweller": ["jewelry", 2, "", 0],
}
var accounts: Dictionary = {}
var stock: Dictionary = {}
var work_minutes: Dictionary = {}
var shortages: Dictionary = {}
var treasury: int = 6000
var settled_day: int = -1
var ledger: Array[Dictionary] = []

func ensure_households(population: TownPopulation, minute: float) -> void:
	if stock.is_empty():
		for good: String in PRICES:
			stock[good] = 100 if good == "food" else 40
	for id: String in population.people:
		var household: String = population.household_for(id)
		if not accounts.has(household):
			accounts[household] = 120
	if settled_day < 0:
		settled_day = floori(minute / 1440.0) - 1

func record_work(id: String, minutes: float) -> void:
	if minutes > 0 and is_finite(minutes):
		work_minutes[id] = minf(600, float(work_minutes.get(id, 0)) + minutes)

func settle(minute: float, population: TownPopulation, dead: Array[String]) -> void:
	var completed_day: int = floori(minute / 1440.0) - 1
	if completed_day <= settled_day:
		return
	# No offline production or repeated payouts for skipped clock days.
	settled_day = completed_day
	shortages.clear()
	var needs: Dictionary = {}
	var ids: Array = population.people.keys()
	ids.sort()
	for id: String in ids:
		if id in dead:
			continue
		var person: Dictionary = population.people[id]
		var house: String = person.household
		needs[house] = int(needs.get(house, 0)) + (1 if person.age < 16 else 2)
		var hours: int = mini(8, int(float(work_minutes.get(id, 0)) / 60.0))
		if person.age < 16 or hours == 0:
			continue
		var recipe: Array = RECIPES.get(person.job, ["", 0, "", 0])
		var batches: int = hours / 4
		if not String(recipe[2]).is_empty():
			batches = mini(batches, int(stock[recipe[2]]) / int(recipe[3]))
			stock[recipe[2]] -= batches * int(recipe[3])
		var units: int = batches * int(recipe[1])
		var earned: int = hours * 2 if String(recipe[0]).is_empty() else units * int(PRICES[recipe[0]])
		if units > 0:
			stock[recipe[0]] += units
		var paid: int = mini(treasury, earned)
		treasury -= paid
		accounts[house] += paid
		_entry("income", house, paid)
	for house: String in needs:
		var portions: int = mini(int(needs[house]), mini(int(stock.food), int(accounts[house]) / int(PRICES.food)))
		var cost: int = portions * int(PRICES.food)
		accounts[house] -= cost
		treasury += cost
		stock.food -= portions
		if portions < needs[house]:
			shortages[house] = int(needs[house]) - portions
		_entry("food", house, -cost)
	work_minutes.clear()

func context(household: String) -> Dictionary:
	return {"household_coins": int(accounts.get(household, 0)),
		"missing_food_portions": int(shortages.get(household, 0)),
		"last_settled_day": settled_day, "trade_available": false}

func _entry(kind: String, household: String, coins: int) -> void:
	ledger.append({"day": settled_day, "kind": kind, "household": household, "coins": coins})
	while ledger.size() > 96:
		ledger.pop_front()

func to_data() -> Dictionary:
	return {"version": 1, "accounts": accounts.duplicate(), "stock": stock.duplicate(),
		"work_minutes": work_minutes.duplicate(), "shortages": shortages.duplicate(),
		"treasury": treasury, "settled_day": settled_day, "ledger": ledger.duplicate(true)}

func from_data(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != 1:
		return false
	for field: String in ["accounts", "stock", "work_minutes", "shortages"]:
		if not data.get(field) is Dictionary or data[field].size() > 512:
			return false
		for id: Variant in data[field]:
			var value: Variant = data[field][id]
			if not id is String or id.is_empty() or not TownLifeState._number(value) or value < 0 or value > 100000000:
				return false
			if field != "work_minutes" and not NpcMemory.is_integer(value):
				return false
	if not data.stock.is_empty():
		if data.stock.size() != PRICES.size():
			return false
		for good: String in PRICES:
			if not data.stock.has(good):
				return false
	if not NpcMemory.is_integer(data.get("treasury")) or data.treasury < 0 \
		or not NpcMemory.is_integer(data.get("settled_day")) or data.settled_day < -1 \
		or not data.get("ledger") is Array or data.ledger.size() > 96:
		return false
	for entry: Variant in data.ledger:
		if not entry is Dictionary or not NpcMemory.is_integer(entry.get("day")) \
			or not NpcMemory.is_integer(entry.get("coins")) or not entry.get("kind") is String \
			or not entry.get("household") is String:
			return false
	accounts = data.accounts.duplicate()
	stock = data.stock.duplicate()
	work_minutes = data.work_minutes.duplicate()
	shortages = data.shortages.duplicate()
	treasury = int(data.treasury)
	settled_day = int(data.settled_day)
	ledger.assign(data.ledger.duplicate(true))
	return true
