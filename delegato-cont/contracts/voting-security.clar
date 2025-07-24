;; Security and Anti-Sybil Voting Contract
;; This contract implements security mechanisms to prevent Sybil attacks and ensure transparent voting

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_ALREADY_VERIFIED (err u101))
(define-constant ERR_NOT_VERIFIED (err u102))
(define-constant ERR_DELEGATION_LOCKED (err u103))
(define-constant ERR_INVALID_TIMELOCK (err u104))
(define-constant ERR_ALREADY_VOTED (err u105))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u106))
(define-constant ERR_INVALID_SHAREHOLDER (err u107))

;; Minimum time lock period (in blocks)
(define-constant MIN_TIMELOCK_PERIOD u144) ;; ~24 hours assuming 10-minute blocks

;; Data Maps

;; Shareholder verification status and identity data
(define-map shareholders
  { address: principal }
  {
    is-verified: bool,
    verification-timestamp: uint,
    identity-hash: (buff 32),
    shares: uint,
    is-active: bool
  }
)

;; Delegation information with time locks
(define-map delegations
  { delegator: principal }
  {
    delegate: principal,
    lock-until-block: uint,
    delegation-timestamp: uint,
    is-active: bool
  }
)

;; Vote records for audit trail
(define-map vote-records
  { voter: principal, proposal-id: uint }
  {
    vote-choice: bool,
    vote-timestamp: uint,
    vote-weight: uint,
    is-delegated: bool,
    original-voter: principal
  }
)

;; Proposal tracking
(define-map proposals
  { proposal-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    created-at: uint,
    voting-ends-at: uint,
    total-votes-for: uint,
    total-votes-against: uint,
    is-active: bool
  }
)

;; Audit log for all voting-related activities
(define-map audit-log
  { log-id: uint }
  {
    action-type: (string-ascii 50),
    actor: principal,
    target: principal,
    proposal-id: (optional uint),
    timestamp: uint,
    details: (string-ascii 200)
  }
)

;; Data Variables
(define-data-var next-proposal-id uint u1)
(define-data-var next-log-id uint u1)
(define-data-var contract-active bool true)

;; Private Functions

;; Generate a unique identity hash for anti-Sybil protection
(define-private (generate-identity-hash (address principal) (verification-data (buff 32)))
  (keccak256 (concat (unwrap-panic (to-consensus-buff? address)) verification-data))
)

;; Check if an identity hash already exists (prevents duplicate verification)
(define-private (identity-hash-exists (hash (buff 32)))
  (let (
    (shareholders-list (list 
      'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM
      'ST1SJ3DTE5DN7X54YDH5D64R3BCB6A2AG2ZQ8YPD5
      'ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG
      'ST2JHG361ZXG51QTKY2NQCVBPPRRE2KZB1HR05NNC
      'ST2NEB84ASENDXKYGJPQW86YXQCEFEX2ZQPG87ND
      'ST2REHHS5J3CERCRBEPMGH7921Q6PYKAADT7JP2VB
      'ST3AM1A56AK2C1XAFJ4115ZSV26EB49BVQ10MGCS0
      'ST3PF13W7Z0RRM42A8VZRVFQ75SV1K26RXEP8YGKJ
      'ST3NBRSFKX28FQ2ZJ1MAKX58HKHSDGNV5N7R21XCP
      'STNHKEPYEPJ8ET55ZZ0M5A34J0R3N5FM2CMMMAZ6
    )) ;; Sample list - in production, this would be dynamically managed
    (result (fold check-shareholder-hash shareholders-list { target-hash: hash, found: false }))
  )
    (get found result)
  )
)

;; Helper function to check if a specific shareholder has the target hash
(define-private (check-shareholder-hash 
  (shareholder-addr principal) 
  (context { target-hash: (buff 32), found: bool })
)
  (if (get found context)
    context ;; Already found, return as-is
    (match (map-get? shareholders { address: shareholder-addr })
      shareholder-data
      (if (is-eq (get identity-hash shareholder-data) (get target-hash context))
        { target-hash: (get target-hash context), found: true }
        context
      )
      context ;; No shareholder data found, continue
    )
  )
)

;; Alternative implementation using a more efficient approach
;; Store used identity hashes in a separate map for O(1) lookup
(define-map used-identity-hashes
  { hash: (buff 32) }
  { used: bool, shareholder: principal }
)

;; Log audit events
(define-private (log-audit-event (action (string-ascii 50)) (actor principal) (target principal) (proposal-id (optional uint)) (details (string-ascii 200)))
  (let ((log-id (var-get next-log-id)))
    (map-set audit-log
      { log-id: log-id }
      {
        action-type: action,
        actor: actor,
        target: target,
        proposal-id: proposal-id,
        timestamp: stacks-block-height,
        details: details
      }
    )
    (var-set next-log-id (+ log-id u1))
    (ok log-id)
  )
)

;; Public Functions

;; Anti-Sybil Protection: Verify shareholder identity (Updated)
(define-public (prevent-sybil (shareholder-address principal) (verification-data (buff 32)) (share-amount uint))
  (let (
    (existing-shareholder (map-get? shareholders { address: shareholder-address }))
    (identity-hash (generate-identity-hash shareholder-address verification-data))
    (hash-already-used (map-get? used-identity-hashes { hash: identity-hash }))
  )
    ;; Check if already verified
    (asserts! (is-none existing-shareholder) ERR_ALREADY_VERIFIED)
    
    ;; Check if identity hash already exists (anti-Sybil check) - more efficient approach
    (asserts! (is-none hash-already-used) ERR_ALREADY_VERIFIED)
    
    ;; Mark the identity hash as used
    (map-set used-identity-hashes
      { hash: identity-hash }
      { used: true, shareholder: shareholder-address }
    )
    
    ;; Verify the shareholder
    (map-set shareholders
      { address: shareholder-address }
      {
        is-verified: true,
        verification-timestamp: stacks-block-height,
        identity-hash: identity-hash,
        shares: share-amount,
        is-active: true
      }
    )
    
    ;; Log the verification event
    (unwrap-panic (log-audit-event 
      "SHAREHOLDER_VERIFIED" 
      tx-sender 
      shareholder-address 
      none 
      "Shareholder identity verified and registered"
    ))
    
    (ok true)
  )
)

;; Updated prevent-sybil function using the efficient hash checking
(define-public (prevent-sybil-v2 (shareholder-address principal) (verification-data (buff 32)) (share-amount uint))
  (let (
    (existing-shareholder (map-get? shareholders { address: shareholder-address }))
    (identity-hash (generate-identity-hash shareholder-address verification-data))
    (hash-already-used (map-get? used-identity-hashes { hash: identity-hash }))
  )
    ;; Check if already verified
    (asserts! (is-none existing-shareholder) ERR_ALREADY_VERIFIED)
    
    ;; Check if identity hash already exists (anti-Sybil check)
    (asserts! (is-none hash-already-used) ERR_ALREADY_VERIFIED)
    
    ;; Mark the identity hash as used
    (map-set used-identity-hashes
      { hash: identity-hash }
      { used: true, shareholder: shareholder-address }
    )
    
    ;; Verify the shareholder
    (map-set shareholders
      { address: shareholder-address }
      {
        is-verified: true,
        verification-timestamp: stacks-block-height,
        identity-hash: identity-hash,
        shares: share-amount,
        is-active: true
      }
    )
    
    ;; Log the verification event
    (unwrap-panic (log-audit-event 
      "SHAREHOLDER_VERIFIED" 
      tx-sender 
      shareholder-address 
      none 
      "Shareholder identity verified and registered"
    ))
    
    (ok true)
  )
)

;; Time Lock for Delegation Changes
(define-public (time-lock-delegation (shareholder-address principal) (delegate-address principal) (lock-time uint))
  (let (
    (shareholder-data (unwrap! (map-get? shareholders { address: shareholder-address }) ERR_INVALID_SHAREHOLDER))
    (existing-delegation (map-get? delegations { delegator: shareholder-address }))
    (lock-until-block (+ stacks-block-height lock-time))
  )
    ;; Ensure caller is the shareholder or contract owner
    (asserts! (or (is-eq tx-sender shareholder-address) (is-eq tx-sender CONTRACT_OWNER)) ERR_UNAUTHORIZED)
    
    ;; Ensure shareholder is verified
    (asserts! (get is-verified shareholder-data) ERR_NOT_VERIFIED)
    
    ;; Ensure minimum time lock period
    (asserts! (>= lock-time MIN_TIMELOCK_PERIOD) ERR_INVALID_TIMELOCK)
    
    ;; Check if there's an existing delegation that's still locked
    (match existing-delegation
      delegation-info
      (asserts! (< (get lock-until-block delegation-info) stacks-block-height) ERR_DELEGATION_LOCKED)
      true
    )
    
    ;; Set the new delegation with time lock
    (map-set delegations
      { delegator: shareholder-address }
      {
        delegate: delegate-address,
        lock-until-block: lock-until-block,
        delegation-timestamp: stacks-block-height,
        is-active: true
      }
    )
    
    ;; Log the delegation event
    (unwrap-panic (log-audit-event 
      "DELEGATION_SET" 
      tx-sender 
      delegate-address 
      none 
      "Vote delegation set with time lock"
    ))
    
    (ok lock-until-block)
  )
)

;; Cast a vote with anti-Sybil and audit mechanisms
(define-public (cast-vote (proposal-id uint) (vote-choice bool))
  (let (
    (voter-data (unwrap! (map-get? shareholders { address: tx-sender }) ERR_NOT_VERIFIED))
    (proposal-data (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR_PROPOSAL_NOT_FOUND))
    (existing-vote (map-get? vote-records { voter: tx-sender, proposal-id: proposal-id }))
    (delegation-info (map-get? delegations { delegator: tx-sender }))
  )
    ;; Ensure shareholder is verified and active
    (asserts! (and (get is-verified voter-data) (get is-active voter-data)) ERR_NOT_VERIFIED)
    
    ;; Ensure proposal is active and voting period hasn't ended
    (asserts! (and (get is-active proposal-data) (< stacks-block-height (get voting-ends-at proposal-data))) ERR_PROPOSAL_NOT_FOUND)
    
    ;; Ensure hasn't already voted
    (asserts! (is-none existing-vote) ERR_ALREADY_VOTED)
    
    ;; Record the vote
    (map-set vote-records
      { voter: tx-sender, proposal-id: proposal-id }
      {
        vote-choice: vote-choice,
        vote-timestamp: stacks-block-height,
        vote-weight: (get shares voter-data),
        is-delegated: false,
        original-voter: tx-sender
      }
    )
    
    ;; Update proposal vote counts
    (if vote-choice
      (map-set proposals
        { proposal-id: proposal-id }
        (merge proposal-data { total-votes-for: (+ (get total-votes-for proposal-data) (get shares voter-data)) })
      )
      (map-set proposals
        { proposal-id: proposal-id }
        (merge proposal-data { total-votes-against: (+ (get total-votes-against proposal-data) (get shares voter-data)) })
      )
    )
    
    ;; Log the vote event
    (unwrap-panic (log-audit-event 
      "VOTE_CAST" 
      tx-sender 
      tx-sender 
      (some proposal-id) 
      "Vote cast on proposal"
    ))
    
    (ok true)
  )
)

;; Audit Votes: Retrieve voting history and audit trail
(define-read-only (audit-votes (voter-address principal) (proposal-id uint))
  (let (
    (vote-record (map-get? vote-records { voter: voter-address, proposal-id: proposal-id }))
    (shareholder-data (map-get? shareholders { address: voter-address }))
  )
    {
      vote-record: vote-record,
      shareholder-data: shareholder-data,
      audit-timestamp: stacks-block-height
    }
  )
)

;; Get comprehensive audit trail for a proposal
(define-read-only (get-proposal-audit-trail (proposal-id uint))
  (let (
    (proposal-data (map-get? proposals { proposal-id: proposal-id }))
  )
    {
      proposal-data: proposal-data,
      audit-timestamp: stacks-block-height
    }
  )
)

;; Administrative Functions

;; Create a new proposal (only contract owner)
(define-public (create-proposal (title (string-ascii 100)) (description (string-ascii 500)) (voting-duration uint))
  (let (
    (proposal-id (var-get next-proposal-id))
    (voting-ends-at (+ stacks-block-height voting-duration))
  )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    
    (map-set proposals
      { proposal-id: proposal-id }
      {
        title: title,
        description: description,
        created-at: stacks-block-height,
        voting-ends-at: voting-ends-at,
        total-votes-for: u0,
        total-votes-against: u0,
        is-active: true
      }
    )
    
    (var-set next-proposal-id (+ proposal-id u1))
    
    ;; Log proposal creation
    (unwrap-panic (log-audit-event 
      "PROPOSAL_CREATED" 
      tx-sender 
      tx-sender 
      (some proposal-id) 
      "New proposal created"
    ))
    
    (ok proposal-id)
  )
)

;; Read-only functions for querying data

(define-read-only (get-shareholder-info (address principal))
  (map-get? shareholders { address: address })
)

(define-read-only (get-delegation-info (delegator principal))
  (map-get? delegations { delegator: delegator })
)

(define-read-only (get-proposal-info (proposal-id uint))
  (map-get? proposals { proposal-id: proposal-id })
)

(define-read-only (get-audit-log-entry (log-id uint))
  (map-get? audit-log { log-id: log-id })
)

;; Check if delegation is currently locked
(define-read-only (is-delegation-locked (delegator principal))
  (match (map-get? delegations { delegator: delegator })
    delegation-info (> (get lock-until-block delegation-info) stacks-block-height)
    false
  )
)

;; Get contract statistics
(define-read-only (get-contract-stats)
  {
    next-proposal-id: (var-get next-proposal-id),
    next-log-id: (var-get next-log-id),
    contract-active: (var-get contract-active),
    current-block: stacks-block-height
  }
)

;; Read-only function to check if an identity hash is already used
(define-read-only (is-identity-hash-used (hash (buff 32)))
  (is-some (map-get? used-identity-hashes { hash: hash }))
)

;; Read-only function to get the shareholder associated with a hash
(define-read-only (get-shareholder-by-hash (hash (buff 32)))
  (map-get? used-identity-hashes { hash: hash })
)
