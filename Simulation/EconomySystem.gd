# EconomySystem.gd
extends Node
class_name EconomySystem

func transfer(from_acc: Account, to_acc: Account, amount: int) -> bool:
	if amount <= 0:
		return true
	if from_acc.balance < amount:
		return false
	from_acc.balance -= amount
	to_acc.balance += amount
	return true
