# EconomySystem.gd
extends Node
class_name EconomySystem

var jobs: Array[Job] = []

func transfer(from_acc: Account, to_acc: Account, amount: int) -> bool:
	if amount <= 0:
		return true
	if from_acc.balance < amount:
		return false
	from_acc.balance -= amount
	to_acc.balance += amount
	return true

func register_job(job: Job) -> void:
	if job == null:
		return
	if jobs.has(job):
		return
	jobs.append(job)

func get_open_jobs() -> Array[Job]:
	var open_jobs: Array[Job] = []
	for job in jobs:
		if job == null:
			continue
		if job.workplace != null and job.workplace.has_free_job_slots():
			open_jobs.append(job)
	return open_jobs
