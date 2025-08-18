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

(define-constant STATUS-SUBMITTED u1)
(define-constant STATUS-APPROVED u2)
(define-constant STATUS-IN-PROGRESS u3)
(define-constant STATUS-COMPLETED u4)
(define-constant STATUS-VERIFIED u5)
(define-constant STATUS-REJECTED u6)

(define-data-var next-request-id uint u1)
(define-data-var contract-owner principal tx-sender)

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
    escrow-amount: uint,
    created-at: uint,
    completed-at: (optional uint)
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
  (evidence-hash (string-ascii 64)))
  (let
    (
      (request-id (var-get next-request-id))
      (tenant tx-sender)
    )
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
        escrow-amount: u0,
        created-at: stacks-block-height,
        completed-at: none
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

(define-public (approve-request (request-id uint) (escrow-amount uint))
  (let
    (
      (request (unwrap! (map-get? maintenance-requests { request-id: request-id }) ERR-REQUEST-NOT-FOUND))
      (landlord tx-sender)
    )
    (asserts! (is-eq (get landlord request) landlord) ERR-NOT-LANDLORD)
    (asserts! (is-eq (get status request) STATUS-SUBMITTED) ERR-INVALID-STATUS)
    (asserts! (> escrow-amount u0) ERR-INVALID-AMOUNT)
    
    (map-set maintenance-requests
      { request-id: request-id }
      (merge request { 
        status: STATUS-APPROVED, 
        escrow-amount: escrow-amount 
      })
    )
    (map-set request-escrow
      { request-id: request-id }
      { amount: escrow-amount, funded: false, released: false }
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
    )
    (asserts! (is-eq (get tenant request) tenant) ERR-NOT-TENANT)
    (asserts! (is-eq (get status request) STATUS-COMPLETED) ERR-INVALID-STATUS)
    (asserts! (not (get released escrow)) ERR-ALREADY-COMPLETED)
    (asserts! (<= contractor-rating u5) ERR-INVALID-AMOUNT)
    (asserts! (<= service-rating u5) ERR-INVALID-AMOUNT)
    
    (try! (as-contract (stx-transfer? (get amount escrow) tx-sender contractor)))
    
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
