extends Node

## Central manager for assigning jobs to Pawns.
## Should be set as an Autoload (Singleton) in Project Settings.

var available_jobs: Array[JobDef] = []
var failed_jobs: Dictionary = {} # job: timestamp_ms
const JOB_FAILURE_COOLDOWN_MS: int = 5000

# Signal to notify when a new job is added (optional, if we want push-based)
signal job_added(job: JobDef)

func _ready() -> void:
	print("JobManager initialized.")

## Registers a new job to the queue
func add_job(job: JobDef) -> void:
	if not job.is_valid():
		push_warning("Attempted to add invalid job.")
		return
	
	# Check for duplicates
	for existing_job in available_jobs:
		if existing_job.target_object == job.target_object and existing_job.job_type == job.job_type:
			return # Job already exists
	
	# If job was previously failed, clear it from failure list so it can be retried immediately
	if job in failed_jobs:
		failed_jobs.erase(job)
	
	available_jobs.append(job)
	emit_signal("job_added", job)
	print("Job added: %s at %s" % [JobDef.JobType.keys()[job.job_type], job.target_position])

## Finds and assigns the closest suitable job for a pawn, respecting priority
func request_job(pawn) -> JobDef:
	var best_job: JobDef = null
	var best_score: float = -INF
	var pawn_pos = pawn.global_position
	var current_time = Time.get_ticks_msec()
	
	# Cleanup old failed jobs
	var jobs_to_clear = []
	for job in failed_jobs:
		if current_time - failed_jobs[job] > JOB_FAILURE_COOLDOWN_MS:
			jobs_to_clear.append(job)
	for job in jobs_to_clear:
		failed_jobs.erase(job)
	
	# Iterate backwards to safely remove if needed
	for i in range(available_jobs.size() - 1, -1, -1):
		var job = available_jobs[i]
		
		# Validation check
		if not job.is_valid():
			available_jobs.remove_at(i)
			continue
			
		# Check failure cooldown
		if job in failed_jobs:
			continue
			
		# Check tool requirement (simplified string check)
		# In a real system, Pawn would have an Inventory/Equipment component
		if job.required_tool != "" and not pawn.has_tool(job.required_tool):
			continue
			
		var dist = pawn_pos.distance_to(job.target_position)
		
		# Score calculation: Priority takes precedence.
		# Priority is usually small integer (0, 1, 2).
		# We want: High Priority > Low Priority.
		# Inside same priority: Short Distance > Long Distance.
		# Score = (Priority * 100000) - Distance
		var score = (job.priority * 100000.0) - dist
		
		if score > best_score:
			best_score = score
			best_job = job
	
	if best_job:
		# Claim the job
		available_jobs.erase(best_job)
		# Mark target as reserved if needed (InteractableObject handles this via Pawn interaction)
		if best_job.target_object is InteractableObject:
			best_job.target_object.reserved_by = pawn
			
		return best_job
	
	return null

## Reports a job as failed by a pawn (e.g. unreachable, no resources)
func report_failed_job(job: JobDef) -> void:
	if not job.is_valid(): return
	
	if job.target_object is InteractableObject:
		job.target_object.reserved_by = null
	
	# Add to failed list with timestamp
	failed_jobs[job] = Time.get_ticks_msec()
	
	# Return to queue
	if not job in available_jobs:
		available_jobs.append(job)
		print("Job returned to queue with FAILURE cooldown: %s" % JobDef.JobType.keys()[job.job_type])

## Gets the pending job for a specific object, if any
func get_job_for_object(obj: Node) -> JobDef:
	for job in available_jobs:
		if job.target_object == obj:
			return job
	return null

## Called when a job is cancelled or interrupted, putting it back in queue
func return_job(job: JobDef) -> void:
	if job.is_valid():
		if job.target_object is InteractableObject:
			job.target_object.reserved_by = null
		
		# Check if job is already in queue to avoid duplicates
		if not job in available_jobs:
			available_jobs.append(job)
			print("Job returned to queue.")

## Alias for return_job, used when a Pawn abandons a job
func cancel_job(job: JobDef) -> void:
	return_job(job)
