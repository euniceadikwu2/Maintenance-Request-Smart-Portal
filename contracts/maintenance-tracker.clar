;; Maintenance Request Smart Contract
;; A comprehensive system for tracking and managing maintenance requests
;; with status updates, priority levels, and cost management

;; Constants for error handling
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-REQUEST-NOT-FOUND (err u101))
(define-constant ERR-INVALID-STATUS (err u102))
(define-constant ERR-INVALID-PRIORITY (err u103))
(define-constant ERR-REQUEST-ALREADY-EXISTS (err u104))
(define-constant ERR-INVALID-COST (err u105))
(define-constant ERR-ALREADY-COMPLETED (err u106))

;; Contract owner for administrative functions
(define-constant CONTRACT-OWNER tx-sender)

;; Data structures
(define-map maintenance-requests
  { request-id: uint }
  {
    requester: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    location: (string-ascii 100),
    priority: (string-ascii 10),
    status: (string-ascii 20),
    created-at: uint,
    updated-at: uint,
    assigned-to: (optional principal),
    estimated-cost: uint,
    actual-cost: (optional uint),
    completion-notes: (optional (string-ascii 300))
  }
)

;; Track request counter for unique IDs
(define-data-var request-counter uint u0)

;; Track total requests by status for analytics
(define-data-var total-pending uint u0)
(define-data-var total-in-progress uint u0)
(define-data-var total-completed uint u0)
(define-data-var total-cancelled uint u0)

;; Helper functions
(define-private (is-valid-priority (priority (string-ascii 10)))
  (or 
    (is-eq priority "low")
    (is-eq priority "medium")
    (is-eq priority "high")
    (is-eq priority "critical")
  )
)

(define-private (is-valid-status (status (string-ascii 20)))
  (or
    (is-eq status "pending")
    (is-eq status "in-progress")
    (is-eq status "completed")
    (is-eq status "cancelled")
  )
)

(define-private (update-status-counters (old-status (string-ascii 20)) (new-status (string-ascii 20)))
  (begin
    ;; Decrement old status counter
    (if (is-eq old-status "pending")
      (var-set total-pending (- (var-get total-pending) u1))
      (if (is-eq old-status "in-progress")
        (var-set total-in-progress (- (var-get total-in-progress) u1))
        (if (is-eq old-status "completed")
          (var-set total-completed (- (var-get total-completed) u1))
          (if (is-eq old-status "cancelled")
            (var-set total-cancelled (- (var-get total-cancelled) u1))
            false
          )
        )
      )
    )
    ;; Increment new status counter
    (if (is-eq new-status "pending")
      (var-set total-pending (+ (var-get total-pending) u1))
      (if (is-eq new-status "in-progress")
        (var-set total-in-progress (+ (var-get total-in-progress) u1))
        (if (is-eq new-status "completed")
          (var-set total-completed (+ (var-get total-completed) u1))
          (if (is-eq new-status "cancelled")
            (var-set total-cancelled (+ (var-get total-cancelled) u1))
            false
          )
        )
      )
    )
  )
)

;; Public functions

;; Create a new maintenance request
(define-public (create-request 
    (title (string-ascii 100))
    (description (string-ascii 500))
    (location (string-ascii 100))
    (priority (string-ascii 10))
    (estimated-cost uint)
  )
  (let
    (
      (new-id (+ (var-get request-counter) u1))
      (current-time stacks-block-height)
    )
    (asserts! (is-valid-priority priority) ERR-INVALID-PRIORITY)
    (asserts! (> estimated-cost u0) ERR-INVALID-COST)
    (asserts! (is-none (map-get? maintenance-requests { request-id: new-id })) ERR-REQUEST-ALREADY-EXISTS)
    
    (map-set maintenance-requests 
      { request-id: new-id }
      {
        requester: tx-sender,
        title: title,
        description: description,
        location: location,
        priority: priority,
        status: "pending",
        created-at: current-time,
        updated-at: current-time,
        assigned-to: none,
        estimated-cost: estimated-cost,
        actual-cost: none,
        completion-notes: none
      }
    )
    
    (var-set request-counter new-id)
    (var-set total-pending (+ (var-get total-pending) u1))
    (ok new-id)
  )
)

;; Update request status (admin or assigned technician only)
(define-public (update-status 
    (request-id uint)
    (new-status (string-ascii 20))
    (notes (optional (string-ascii 300)))
  )
  (let
    (
      (request (unwrap! (map-get? maintenance-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (current-time stacks-block-height)
      (old-status (get status request))
    )
    (asserts! (is-valid-status new-status) ERR-INVALID-STATUS)
    (asserts! 
      (or 
        (is-eq tx-sender CONTRACT-OWNER)
        (is-eq (some tx-sender) (get assigned-to request))
        (is-eq tx-sender (get requester request))
      ) 
      ERR-NOT-AUTHORIZED
    )
    (asserts! (not (is-eq old-status "completed")) ERR-ALREADY-COMPLETED)
    
    (map-set maintenance-requests
      { request-id: request-id }
      (merge request {
        status: new-status,
        updated-at: current-time,
        completion-notes: (if (is-eq new-status "completed") notes (get completion-notes request))
      })
    )
    
    (update-status-counters old-status new-status)
    (ok true)
  )
)

;; Assign technician to request (admin only)
(define-public (assign-technician (request-id uint) (technician principal))
  (let
    (
      (request (unwrap! (map-get? maintenance-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (current-time stacks-block-height)
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    
    (map-set maintenance-requests
      { request-id: request-id }
      (merge request {
        assigned-to: (some technician),
        updated-at: current-time,
        status: "in-progress"
      })
    )
    
    (update-status-counters (get status request) "in-progress")
    (ok true)
  )
)

;; Update actual cost (assigned technician or admin only)
(define-public (update-actual-cost (request-id uint) (cost uint))
  (let
    (
      (request (unwrap! (map-get? maintenance-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (current-time stacks-block-height)
    )
    (asserts! (> cost u0) ERR-INVALID-COST)
    (asserts! 
      (or 
        (is-eq tx-sender CONTRACT-OWNER)
        (is-eq (some tx-sender) (get assigned-to request))
      ) 
      ERR-NOT-AUTHORIZED
    )
    
    (map-set maintenance-requests
      { request-id: request-id }
      (merge request {
        actual-cost: (some cost),
        updated-at: current-time
      })
    )
    
    (ok true)
  )
)

;; Read-only functions

;; Get request details
(define-read-only (get-request (request-id uint))
  (map-get? maintenance-requests { request-id: request-id })
)

;; Get current request counter
(define-read-only (get-request-count)
  (var-get request-counter)
)

;; Get analytics data
(define-read-only (get-analytics)
  {
    total-requests: (var-get request-counter),
    pending: (var-get total-pending),
    in-progress: (var-get total-in-progress),
    completed: (var-get total-completed),
    cancelled: (var-get total-cancelled)
  }
)

;; Check if user can modify request
(define-read-only (can-modify-request (request-id uint) (user principal))
  (match (map-get? maintenance-requests { request-id: request-id })
    request (or
      (is-eq user CONTRACT-OWNER)
      (is-eq user (get requester request))
      (is-eq (some user) (get assigned-to request))
    )
    false
  )
)

;; Get requests by status (simplified version - returns count)
(define-read-only (get-requests-by-status (status (string-ascii 20)))
  (if (is-eq status "pending")
    (var-get total-pending)
    (if (is-eq status "in-progress")
      (var-get total-in-progress)
      (if (is-eq status "completed")
        (var-get total-completed)
        (if (is-eq status "cancelled")
          (var-get total-cancelled)
          u0
        )
      )
    )
  )
)

;; =================================================================
;; MAINTENANCE SCHEDULING SYSTEM - New Independent Feature
;; =================================================================

;; Additional error constants for scheduling
(define-constant ERR-SCHEDULE-NOT-FOUND (err u200))
(define-constant ERR-INVALID-INTERVAL (err u201))
(define-constant ERR-SCHEDULE-ALREADY-EXISTS (err u202))
(define-constant ERR-INVALID-FREQUENCY (err u203))
(define-constant ERR-SCHEDULE-INACTIVE (err u204))

;; Error constants for rating system
(define-constant ERR-INVALID-RATING (err u300))
(define-constant ERR-RATING-ALREADY-EXISTS (err u301))
(define-constant ERR-NOT-COMPLETED (err u302))
(define-constant ERR-NOT-REQUESTER (err u303))

;; Scheduled maintenance tasks data structure
(define-map scheduled-maintenance
  { schedule-id: uint }
  {
    creator: principal,
    task-name: (string-ascii 100),
    description: (string-ascii 300),
    location: (string-ascii 100),
    frequency: (string-ascii 20),
    interval-days: uint,
    next-due-date: uint,
    last-completed: (optional uint),
    assigned-technician: (optional principal),
    estimated-hours: uint,
    is-active: bool,
    created-at: uint,
    total-completions: uint
  }
)

;; Schedule counter for unique IDs
(define-data-var schedule-counter uint u0)

;; Track active schedules count
(define-data-var active-schedules uint u0)

;; Helper functions for scheduling
(define-private (is-valid-frequency (frequency (string-ascii 20)))
  (or
    (is-eq frequency "daily")
    (is-eq frequency "weekly")
    (is-eq frequency "monthly")
    (is-eq frequency "quarterly")
    (is-eq frequency "yearly")
    (is-eq frequency "custom")
  )
)

(define-private (calculate-next-due-date (current-date uint) (frequency (string-ascii 20)) (interval-days uint))
  (if (is-eq frequency "custom")
    (+ current-date interval-days)
    (if (is-eq frequency "daily")
      (+ current-date u1)
      (if (is-eq frequency "weekly")
        (+ current-date u7)
        (if (is-eq frequency "monthly")
          (+ current-date u30)
          (if (is-eq frequency "quarterly")
            (+ current-date u90)
            (+ current-date u365) ;; yearly
          )
        )
      )
    )
  )
)

;; Public functions for scheduling

;; Create a new scheduled maintenance task
(define-public (create-schedule
    (task-name (string-ascii 100))
    (description (string-ascii 300))
    (location (string-ascii 100))
    (frequency (string-ascii 20))
    (interval-days uint)
    (estimated-hours uint)
  )
  (let
    (
      (new-id (+ (var-get schedule-counter) u1))
      (current-time stacks-block-height)
    )
    (asserts! (is-valid-frequency frequency) ERR-INVALID-FREQUENCY)
    (asserts! (> estimated-hours u0) ERR-INVALID-COST)
    (asserts! (if (is-eq frequency "custom") (> interval-days u0) true) ERR-INVALID-INTERVAL)
    (asserts! (is-none (map-get? scheduled-maintenance { schedule-id: new-id })) ERR-SCHEDULE-ALREADY-EXISTS)
    
    (map-set scheduled-maintenance
      { schedule-id: new-id }
      {
        creator: tx-sender,
        task-name: task-name,
        description: description,
        location: location,
        frequency: frequency,
        interval-days: interval-days,
        next-due-date: (calculate-next-due-date current-time frequency interval-days),
        last-completed: none,
        assigned-technician: none,
        estimated-hours: estimated-hours,
        is-active: true,
        created-at: current-time,
        total-completions: u0
      }
    )
    
    (var-set schedule-counter new-id)
    (var-set active-schedules (+ (var-get active-schedules) u1))
    (ok new-id)
  )
)

;; Assign technician to scheduled task (admin only)
(define-public (assign-schedule-technician (schedule-id uint) (technician principal))
  (let
    (
      (schedule (unwrap! (map-get? scheduled-maintenance { schedule-id: schedule-id }) ERR-SCHEDULE-NOT-FOUND))
      (current-time stacks-block-height)
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (get is-active schedule) ERR-SCHEDULE-INACTIVE)
    
    (map-set scheduled-maintenance
      { schedule-id: schedule-id }
      (merge schedule {
        assigned-technician: (some technician)
      })
    )
    
    (ok true)
  )
)

;; Mark scheduled task as completed
(define-public (complete-scheduled-task (schedule-id uint))
  (let
    (
      (schedule (unwrap! (map-get? scheduled-maintenance { schedule-id: schedule-id }) ERR-SCHEDULE-NOT-FOUND))
      (current-time stacks-block-height)
    )
    (asserts! 
      (or 
        (is-eq tx-sender CONTRACT-OWNER)
        (is-eq (some tx-sender) (get assigned-technician schedule))
        (is-eq tx-sender (get creator schedule))
      ) 
      ERR-NOT-AUTHORIZED
    )
    (asserts! (get is-active schedule) ERR-SCHEDULE-INACTIVE)
    
    (map-set scheduled-maintenance
      { schedule-id: schedule-id }
      (merge schedule {
        last-completed: (some current-time),
        next-due-date: (calculate-next-due-date current-time (get frequency schedule) (get interval-days schedule)),
        total-completions: (+ (get total-completions schedule) u1)
      })
    )
    
    (ok true)
  )
)

;; Toggle schedule active status (admin or creator only)
(define-public (toggle-schedule-status (schedule-id uint))
  (let
    (
      (schedule (unwrap! (map-get? scheduled-maintenance { schedule-id: schedule-id }) ERR-SCHEDULE-NOT-FOUND))
      (current-active (get is-active schedule))
    )
    (asserts! 
      (or 
        (is-eq tx-sender CONTRACT-OWNER)
        (is-eq tx-sender (get creator schedule))
      ) 
      ERR-NOT-AUTHORIZED
    )
    
    (map-set scheduled-maintenance
      { schedule-id: schedule-id }
      (merge schedule {
        is-active: (not current-active)
      })
    )
    
    ;; Update active schedules counter
    (if current-active
      (var-set active-schedules (- (var-get active-schedules) u1))
      (var-set active-schedules (+ (var-get active-schedules) u1))
    )
    
    (ok (not current-active))
  )
)

;; Read-only functions for scheduling

;; Get schedule details
(define-read-only (get-schedule (schedule-id uint))
  (map-get? scheduled-maintenance { schedule-id: schedule-id })
)

;; Get current schedule counter
(define-read-only (get-schedule-count)
  (var-get schedule-counter)
)

;; Get scheduling analytics
(define-read-only (get-schedule-analytics)
  {
    total-schedules: (var-get schedule-counter),
    active-schedules: (var-get active-schedules),
    inactive-schedules: (- (var-get schedule-counter) (var-get active-schedules))
  }
)

;; Check if schedule is overdue
(define-read-only (is-schedule-overdue (schedule-id uint))
  (match (map-get? scheduled-maintenance { schedule-id: schedule-id })
    schedule (and
      (get is-active schedule)
      (< (get next-due-date schedule) stacks-block-height)
    )
    false
  )
)

;; Get overdue schedules count (simplified)
(define-read-only (get-overdue-count)
  ;; This is a simplified implementation that would need iteration in a full system
  ;; For demo purposes, returns a placeholder
  u0
)

;; Check if user can manage schedule
(define-read-only (can-manage-schedule (schedule-id uint) (user principal))
  (match (map-get? scheduled-maintenance { schedule-id: schedule-id })
    schedule (or
      (is-eq user CONTRACT-OWNER)
      (is-eq user (get creator schedule))
      (is-eq (some user) (get assigned-technician schedule))
    )
    false
  )
)

;; =================================================================
;; RATING & FEEDBACK SYSTEM - New Independent Feature
;; =================================================================

(define-map request-ratings
  { request-id: uint }
  {
    rating: uint,
    feedback: (string-ascii 500),
    rated-by: principal,
    rated-at: uint,
    quality-score: uint,
    timeliness-score: uint,
    professionalism-score: uint
  }
)

(define-map technician-performance
  { technician: principal }
  {
    total-ratings: uint,
    average-rating: uint,
    total-score: uint,
    completed-tasks: uint,
    excellent-ratings: uint,
    poor-ratings: uint
  }
)

(define-private (is-valid-rating-value (rating uint))
  (and (>= rating u1) (<= rating u5))
)

(define-private (calculate-overall-rating (quality uint) (timeliness uint) (professionalism uint))
  (/ (+ quality timeliness professionalism) u3)
)

(define-public (rate-completed-request
    (request-id uint)
    (quality-score uint)
    (timeliness-score uint)
    (professionalism-score uint)
    (feedback (string-ascii 500))
  )
  (let
    (
      (request (unwrap! (map-get? maintenance-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (current-time stacks-block-height)
      (overall-rating (calculate-overall-rating quality-score timeliness-score professionalism-score))
    )
    (asserts! (is-eq tx-sender (get requester request)) ERR-NOT-REQUESTER)
    (asserts! (is-eq (get status request) "completed") ERR-NOT-COMPLETED)
    (asserts! (is-none (map-get? request-ratings { request-id: request-id })) ERR-RATING-ALREADY-EXISTS)
    (asserts! (is-valid-rating-value quality-score) ERR-INVALID-RATING)
    (asserts! (is-valid-rating-value timeliness-score) ERR-INVALID-RATING)
    (asserts! (is-valid-rating-value professionalism-score) ERR-INVALID-RATING)
    
    (map-set request-ratings
      { request-id: request-id }
      {
        rating: overall-rating,
        feedback: feedback,
        rated-by: tx-sender,
        rated-at: current-time,
        quality-score: quality-score,
        timeliness-score: timeliness-score,
        professionalism-score: professionalism-score
      }
    )
    
    (match (get assigned-to request)
      technician (update-technician-performance technician overall-rating)
      true
    )
    
    (ok overall-rating)
  )
)

(define-private (update-technician-performance (technician principal) (new-rating uint))
  (let
    (
      (current-perf (default-to 
        {
          total-ratings: u0,
          average-rating: u0,
          total-score: u0,
          completed-tasks: u0,
          excellent-ratings: u0,
          poor-ratings: u0
        }
        (map-get? technician-performance { technician: technician })
      ))
      (new-total-ratings (+ (get total-ratings current-perf) u1))
      (new-total-score (+ (get total-score current-perf) new-rating))
      (new-average (/ new-total-score new-total-ratings))
      (new-excellent (if (>= new-rating u4) (+ (get excellent-ratings current-perf) u1) (get excellent-ratings current-perf)))
      (new-poor (if (<= new-rating u2) (+ (get poor-ratings current-perf) u1) (get poor-ratings current-perf)))
    )
    (map-set technician-performance
      { technician: technician }
      {
        total-ratings: new-total-ratings,
        average-rating: new-average,
        total-score: new-total-score,
        completed-tasks: (+ (get completed-tasks current-perf) u1),
        excellent-ratings: new-excellent,
        poor-ratings: new-poor
      }
    )
  )
)

(define-read-only (get-request-rating (request-id uint))
  (map-get? request-ratings { request-id: request-id })
)

(define-read-only (get-technician-performance (technician principal))
  (map-get? technician-performance { technician: technician })
)

(define-read-only (has-request-been-rated (request-id uint))
  (is-some (map-get? request-ratings { request-id: request-id }))
)

(define-read-only (can-rate-request (request-id uint) (user principal))
  (match (map-get? maintenance-requests { request-id: request-id })
    request (and
      (is-eq user (get requester request))
      (is-eq (get status request) "completed")
      (not (has-request-been-rated request-id))
    )
    false
  )
)

(define-read-only (get-technician-rating-summary (technician principal))
  (match (map-get? technician-performance { technician: technician })
    perf {
      average-rating: (get average-rating perf),
      total-ratings: (get total-ratings perf),
      completed-tasks: (get completed-tasks perf),
      excellence-rate: (if (> (get total-ratings perf) u0)
        (/ (* (get excellent-ratings perf) u100) (get total-ratings perf))
        u0
      ),
      poor-rate: (if (> (get total-ratings perf) u0)
        (/ (* (get poor-ratings perf) u100) (get total-ratings perf))
        u0
      )
    }
    {
      average-rating: u0,
      total-ratings: u0,
      completed-tasks: u0,
      excellence-rate: u0,
      poor-rate: u0
    }
  )
)
