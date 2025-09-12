(define-constant ERR-NOT-AUTHORIZED (err u1))
(define-constant ERR-REQUEST-NOT-FOUND (err u2))
(define-constant ERR-INVALID-STATUS (err u3))
(define-constant ERR-INSUFFICIENT-FUNDS (err u4))
(define-constant ERR-ALREADY-COMPLETED (err u5))
(define-constant ERR-NOT-TENANT (err u6))
(define-constant ERR-NOT-LANDLORD (err u7))
(define-constant ERR-NOT-CONTRACTOR (err u8))
(define-constant ERR-ESCROW-NOT-FUNDED (err u9))
(define-constant ERR-INVALID-AMOUNT (err u10))
(define-constant ERR-INSUFFICIENT-SIGNERS (err u11))
(define-constant ERR-ALREADY-SIGNED (err u12))
(define-constant ERR-INVALID-THRESHOLD (err u13))
(define-constant ERR-NOT-AUTHORIZED-SIGNER (err u14))
(define-constant ERR-INVALID-PRIORITY (err u15))
(define-constant ERR-SLA-VIOLATED (err u16))
(define-constant ERR-INSUFFICIENT-PENALTY (err u17))

(define-constant STATUS-SUBMITTED u1)
(define-constant STATUS-APPROVED u2)
(define-constant STATUS-IN-PROGRESS u3)
(define-constant STATUS-COMPLETED u4)
(define-constant STATUS-VERIFIED u5)
(define-constant STATUS-REJECTED u6)

(define-constant PRIORITY-EMERGENCY u1)
(define-constant PRIORITY-URGENT u2)
(define-constant PRIORITY-NORMAL u3)
(define-constant PRIORITY-LOW u4)

(define-data-var next-request-id uint u1)
(define-data-var contract-owner principal tx-sender)
(define-data-var penalty-pool uint u0)

(define-map maintenance-requests
  { request-id: uint }
  {
    tenant: principal,
    landlord: principal,
    contractor: (optional principal),
    title: (string-ascii 100),
    description: (string-ascii 500),
    evidence-hash: (string-ascii 64),
    status: uint,
    priority: uint,
    escrow-amount: uint,
    created-at: uint,
    completed-at: (optional uint),
    approved-at: (optional uint),
    sla-deadline: uint
  }
)

(define-map request-escrow
  { request-id: uint }
  {
    amount: uint,
    funded: bool,
    released: bool
  }
)

(define-map tenant-ratings
  { tenant: principal, request-id: uint }
  {
    contractor-rating: uint,
    service-rating: uint,
    completion-time: uint
  }
)

(define-map landlord-properties
  { landlord: principal, property-id: uint }
  {
    tenant: principal,
    property-address: (string-ascii 200)
  }
)

(define-map property-counter
  { landlord: principal }
  { count: uint }
)

(define-map multisig-configs
  { request-id: uint }
  {
    required-signatures: uint,
    threshold-amount: uint,
    signers: (list 10 principal),
    created-at: uint
  }
)

(define-map multisig-approvals
  { request-id: uint, signer: principal }
  { approved: bool, signed-at: uint }
)

(define-map priority-penalties
  { landlord: principal }
  {
    total-penalties: uint,
    violation-count: uint,
    last-violation: uint
  }
)

(define-map contractor-bonuses
  { contractor: principal, request-id: uint }
  {
    bonus-amount: uint,
    early-completion: bool,
    time-saved: uint
  }
)

(define-data-var multisig-threshold uint u1000000)

(define-public (register-property (tenant principal) (property-address (string-ascii 200)))
  (let
    (
      (landlord tx-sender)
      (current-count (default-to u0 (get count (map-get? property-counter { landlord: landlord }))))
      (new-property-id (+ current-count u1))
    )
    (map-set landlord-properties
      { landlord: landlord, property-id: new-property-id }
      { tenant: tenant, property-address: property-address }
    )
    (map-set property-counter
      { landlord: landlord }
      { count: new-property-id }
    )
    (ok new-property-id)
  )
)

(define-public (submit-request 
  (landlord principal) 
  (title (string-ascii 100)) 
  (description (string-ascii 500)) 
  (evidence-hash (string-ascii 64))
  (priority uint))
  (let
    (
      (request-id (var-get next-request-id))
      (tenant tx-sender)
      (sla-blocks (get-sla-blocks priority))
    )
    (asserts! (and (>= priority PRIORITY-EMERGENCY) (<= priority PRIORITY-LOW)) ERR-INVALID-PRIORITY)
    (map-set maintenance-requests
      { request-id: request-id }
      {
        tenant: tenant,
        landlord: landlord,
        contractor: none,
        title: title,
        description: description,
        evidence-hash: evidence-hash,
        status: STATUS-SUBMITTED,
        priority: priority,
        escrow-amount: u0,
        created-at: stacks-block-height,
        completed-at: none,
        approved-at: none,
        sla-deadline: (+ stacks-block-height sla-blocks)
      }
    )
    (var-set next-request-id (+ request-id u1))
    (ok request-id)
  )
)

(define-public (setup-multisig (request-id uint) (signers (list 10 principal)) (required-sigs uint))
  (let
    (
      (request (unwrap! (map-get? maintenance-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (landlord tx-sender)
      (escrow-amount (get escrow-amount request))
    )
    (asserts! (is-eq (get landlord request) landlord) ERR-NOT-LANDLORD)
    (asserts! (>= escrow-amount (var-get multisig-threshold)) ERR-INVALID-AMOUNT)
    (asserts! (> required-sigs u0) ERR-INVALID-THRESHOLD)
    (asserts! (<= required-sigs (len signers)) ERR-INVALID-THRESHOLD)
    
    (map-set multisig-configs
      { request-id: request-id }
      {
        required-signatures: required-sigs,
        threshold-amount: escrow-amount,
        signers: signers,
        created-at: stacks-block-height
      }
    )
    (ok true)
  )
)

(define-public (multisig-sign (request-id uint))
  (let
    (
      (config (unwrap! (map-get? multisig-configs { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (signer tx-sender)
      (existing-approval (map-get? multisig-approvals { request-id: request-id, signer: signer }))
    )
    (asserts! (is-some (index-of (get signers config) signer)) ERR-NOT-AUTHORIZED-SIGNER)
    (asserts! (is-none existing-approval) ERR-ALREADY-SIGNED)
    
    (map-set multisig-approvals
      { request-id: request-id, signer: signer }
      { approved: true, signed-at: stacks-block-height }
    )
    (ok true)
  )
)

(define-read-only (check-multisig-status (request-id uint))
  (let
    (
      (config (unwrap! (map-get? multisig-configs { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (signers (get signers config))
      (required-sigs (get required-signatures config))
    )
    (ok {
      signatures: (fold count-signatures signers u0),
      required: required-sigs,
      complete: (>= (fold count-signatures signers u0) required-sigs)
    })
  )
)

(define-private (count-signatures (signer principal) (acc uint))
  (+ acc u1)
)

(define-private (get-sla-blocks (priority uint))
  (if (is-eq priority PRIORITY-EMERGENCY)
    u6
    (if (is-eq priority PRIORITY-URGENT)
      u144
      (if (is-eq priority PRIORITY-NORMAL)
        u1008
        u2016))))

(define-private (calculate-penalty-amount (priority uint) (escrow-amount uint))
  (if (is-eq priority PRIORITY-EMERGENCY)
    (/ (* escrow-amount u50) u100)
    (if (is-eq priority PRIORITY-URGENT)
      (/ (* escrow-amount u30) u100)
      (/ (* escrow-amount u15) u100))))

(define-private (calculate-bonus-amount (priority uint) (escrow-amount uint) (time-saved uint))
  (let
    (
      (base-bonus (if (is-eq priority PRIORITY-EMERGENCY)
        (/ (* escrow-amount u20) u100)
        (if (is-eq priority PRIORITY-URGENT)
          (/ (* escrow-amount u15) u100)
          (/ (* escrow-amount u10) u100))))
    )
    (if (> time-saved u0)
      (+ base-bonus (/ (* base-bonus time-saved) u100))
      base-bonus)))

(define-public (approve-request (request-id uint) (escrow-amount uint))
  (let
    (
      (request (unwrap! (map-get? maintenance-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (landlord tx-sender)
      (current-block stacks-block-height)
      (sla-deadline (get sla-deadline request))
      (priority (get priority request))
      (sla-violated (> current-block sla-deadline))
      (penalty-amount (if sla-violated (calculate-penalty-amount priority escrow-amount) u0))
      (total-escrow (+ escrow-amount penalty-amount))
    )
    (asserts! (is-eq (get landlord request) landlord) ERR-NOT-LANDLORD)
    (asserts! (is-eq (get status request) STATUS-SUBMITTED) ERR-INVALID-STATUS)
    (asserts! (> escrow-amount u0) ERR-INVALID-AMOUNT)
    
    (if sla-violated
      (begin
        (try! (stx-transfer? penalty-amount landlord (as-contract tx-sender)))
        (var-set penalty-pool (+ (var-get penalty-pool) penalty-amount))
        (map-set priority-penalties
          { landlord: landlord }
          {
            total-penalties: (+ penalty-amount (default-to u0 (get total-penalties (map-get? priority-penalties { landlord: landlord })))),
            violation-count: (+ u1 (default-to u0 (get violation-count (map-get? priority-penalties { landlord: landlord })))),
            last-violation: current-block
          })
      )
      true
    )
    
    (map-set maintenance-requests
      { request-id: request-id }
      (merge request { 
        status: STATUS-APPROVED, 
        escrow-amount: total-escrow,
        approved-at: (some current-block)
      })
    )
    (map-set request-escrow
      { request-id: request-id }
      { amount: total-escrow, funded: false, released: false }
    )
    (ok true)
  )
)

(define-public (fund-escrow (request-id uint))
  (let
    (
      (request (unwrap! (map-get? maintenance-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (escrow (unwrap! (map-get? request-escrow { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (landlord tx-sender)
    )
    (asserts! (is-eq (get landlord request) landlord) ERR-NOT-LANDLORD)
    (asserts! (is-eq (get status request) STATUS-APPROVED) ERR-INVALID-STATUS)
    (asserts! (not (get funded escrow)) ERR-ALREADY-COMPLETED)
    
    (try! (stx-transfer? (get amount escrow) landlord (as-contract tx-sender)))
    
    (map-set request-escrow
      { request-id: request-id }
      (merge escrow { funded: true })
    )
    (ok true)
  )
)

(define-public (assign-contractor (request-id uint) (contractor principal))
  (let
    (
      (request (unwrap! (map-get? maintenance-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (escrow (unwrap! (map-get? request-escrow { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (landlord tx-sender)
    )
    (asserts! (is-eq (get landlord request) landlord) ERR-NOT-LANDLORD)
    (asserts! (is-eq (get status request) STATUS-APPROVED) ERR-INVALID-STATUS)
    (asserts! (get funded escrow) ERR-ESCROW-NOT-FUNDED)
    
    (map-set maintenance-requests
      { request-id: request-id }
      (merge request { 
        contractor: (some contractor),
        status: STATUS-IN-PROGRESS
      })
    )
    (ok true)
  )
)

(define-public (mark-completed (request-id uint))
  (let
    (
      (request (unwrap! (map-get? maintenance-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (contractor tx-sender)
    )
    (asserts! (is-eq (some contractor) (get contractor request)) ERR-NOT-CONTRACTOR)
    (asserts! (is-eq (get status request) STATUS-IN-PROGRESS) ERR-INVALID-STATUS)
    
    (map-set maintenance-requests
      { request-id: request-id }
      (merge request { 
        status: STATUS-COMPLETED,
        completed-at: (some stacks-block-height)
      })
    )
    (ok true)
  )
)

(define-public (verify-completion (request-id uint) (contractor-rating uint) (service-rating uint))
  (let
    (
      (request (unwrap! (map-get? maintenance-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (escrow (unwrap! (map-get? request-escrow { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (tenant tx-sender)
      (contractor (unwrap! (get contractor request) ERR-NOT-CONTRACTOR))
      (completion-time (- stacks-block-height (get created-at request)))
      (priority (get priority request))
      (expected-completion (get-sla-blocks priority))
      (early-completion (< completion-time expected-completion))
      (time-saved (if early-completion (- expected-completion completion-time) u0))
      (bonus-amount (if early-completion (calculate-bonus-amount priority (get amount escrow) time-saved) u0))
      (base-payment (get amount escrow))
      (total-payment (+ base-payment bonus-amount))
    )
    (asserts! (is-eq (get tenant request) tenant) ERR-NOT-TENANT)
    (asserts! (is-eq (get status request) STATUS-COMPLETED) ERR-INVALID-STATUS)
    (asserts! (not (get released escrow)) ERR-ALREADY-COMPLETED)
    (asserts! (<= contractor-rating u5) ERR-INVALID-AMOUNT)
    (asserts! (<= service-rating u5) ERR-INVALID-AMOUNT)
    
    (try! (as-contract (stx-transfer? base-payment tx-sender contractor)))
    
    (if early-completion
      (begin
        (try! (as-contract (stx-transfer? bonus-amount tx-sender contractor)))
        (var-set penalty-pool (- (var-get penalty-pool) bonus-amount))
        (map-set contractor-bonuses
          { contractor: contractor, request-id: request-id }
          {
            bonus-amount: bonus-amount,
            early-completion: true,
            time-saved: time-saved
          })
      )
      true
    )
    
    (map-set maintenance-requests
      { request-id: request-id }
      (merge request { status: STATUS-VERIFIED })
    )
    
    (map-set request-escrow
      { request-id: request-id }
      (merge escrow { released: true })
    )
    
    (map-set tenant-ratings
      { tenant: tenant, request-id: request-id }
      {
        contractor-rating: contractor-rating,
        service-rating: service-rating,
        completion-time: completion-time
      }
    )
    (ok true)
  )
)

(define-public (reject-completion (request-id uint))
  (let
    (
      (request (unwrap! (map-get? maintenance-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (tenant tx-sender)
    )
    (asserts! (is-eq (get tenant request) tenant) ERR-NOT-TENANT)
    (asserts! (is-eq (get status request) STATUS-COMPLETED) ERR-INVALID-STATUS)
    
    (map-set maintenance-requests
      { request-id: request-id }
      (merge request { status: STATUS-IN-PROGRESS })
    )
    (ok true)
  )
)

(define-public (emergency-release (request-id uint))
  (let
    (
      (request (unwrap! (map-get? maintenance-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (escrow (unwrap! (map-get? request-escrow { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (landlord tx-sender)
      (contractor (unwrap! (get contractor request) ERR-NOT-CONTRACTOR))
    )
    (asserts! (is-eq (get landlord request) landlord) ERR-NOT-LANDLORD)
    (asserts! (not (get released escrow)) ERR-ALREADY-COMPLETED)
    (asserts! (>= (- stacks-block-height (get created-at request)) u1008) ERR-INVALID-STATUS)
    
    (try! (as-contract (stx-transfer? (get amount escrow) tx-sender contractor)))
    
    (map-set request-escrow
      { request-id: request-id }
      (merge escrow { released: true })
    )
    (ok true)
  )
)

(define-read-only (get-request (request-id uint))
  (map-get? maintenance-requests { request-id: request-id })
)

(define-read-only (get-escrow-status (request-id uint))
  (map-get? request-escrow { request-id: request-id })
)

(define-read-only (get-rating (tenant principal) (request-id uint))
  (map-get? tenant-ratings { tenant: tenant, request-id: request-id })
)

(define-read-only (get-property (landlord principal) (property-id uint))
  (map-get? landlord-properties { landlord: landlord, property-id: property-id })
)

(define-read-only (get-next-request-id)
  (var-get next-request-id)
)

(define-read-only (get-property-count (landlord principal))
  (default-to u0 (get count (map-get? property-counter { landlord: landlord })))
)

(define-read-only (get-multisig-config (request-id uint))
  (map-get? multisig-configs { request-id: request-id })
)

(define-read-only (get-signer-approval (request-id uint) (signer principal))
  (map-get? multisig-approvals { request-id: request-id, signer: signer })
)

(define-read-only (get-multisig-threshold)
  (var-get multisig-threshold)
)

(define-read-only (get-priority-name (priority uint))
  (if (is-eq priority PRIORITY-EMERGENCY)
    "Emergency"
    (if (is-eq priority PRIORITY-URGENT)
      "Urgent"
      (if (is-eq priority PRIORITY-NORMAL)
        "Normal"
        "Low")))
)

(define-read-only (get-sla-deadline (priority uint))
  (+ stacks-block-height (get-sla-blocks priority))
)

(define-read-only (get-penalty-info (landlord principal))
  (map-get? priority-penalties { landlord: landlord })
)

(define-read-only (get-contractor-bonus (contractor principal) (request-id uint))
  (map-get? contractor-bonuses { contractor: contractor, request-id: request-id })
)

(define-read-only (get-penalty-pool-balance)
  (var-get penalty-pool)
)

(define-read-only (check-sla-status (request-id uint))
  (let
    (
      (request (unwrap! (map-get? maintenance-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (current-block stacks-block-height)
      (sla-deadline (get sla-deadline request))
      (status (get status request))
    )
    (ok {
      sla-deadline: sla-deadline,
      current-block: current-block,
      blocks-remaining: (if (> sla-deadline current-block) (- sla-deadline current-block) u0),
      sla-violated: (and (> current-block sla-deadline) (is-eq status STATUS-SUBMITTED)),
      priority: (get priority request)
    })
  )
)
