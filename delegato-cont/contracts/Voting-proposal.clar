
;; title: Voting-proposal
;; version:
;; summary:
;; description:

;; Voting Proposal Management Smart Contract
;; This contract allows for the creation and management of voting proposals

;; Error codes
(define-constant ERR_UNAUTHORIZED u1)
(define-constant ERR_INVALID_PROPOSAL u2)
(define-constant ERR_PROPOSAL_CLOSED u3)
(define-constant ERR_PROPOSAL_NOT_STARTED u4)
(define-constant ERR_ALREADY_VOTED u5)
(define-constant ERR_INSUFFICIENT_VOTING_POWER u6)

;; Proposal status constants
(define-constant STATUS_PENDING u0)
(define-constant STATUS_ACTIVE u1)
(define-constant STATUS_CLOSED u2)
(define-constant STATUS_REJECTED u3)
(define-constant STATUS_APPROVED u4)

;; Data structures
(define-map proposals
  { proposal-id: uint }
  {
    title: (string-utf8 256),
    description: (string-utf8 1024),
    creator: principal,
    start-time: uint,
    end-time: uint,
    status: uint,
    yes-votes: uint,
    no-votes: uint,
    total-votes: uint
  }
)

(define-map votes
  { proposal-id: uint, voter: principal }
  {
    vote-option: bool,
    vote-amount: uint,
    timestamp: uint
  }
)

;; Keep track of the next proposal ID
(define-data-var next-proposal-id uint u1)

;; Function to create a new proposal
(define-public (create-proposal (title (string-utf8 256)) (description (string-utf8 1024)) (start-time uint) (end-time uint))
  (let
    (
      (proposal-id (var-get next-proposal-id))
    )
    ;; Validate inputs
    (asserts! (> end-time start-time) (err ERR_INVALID_PROPOSAL))
    (asserts! (>= start-time block-height) (err ERR_INVALID_PROPOSAL))
    
    ;; Create the proposal
    (map-set proposals
      { proposal-id: proposal-id }
      {
        title: title,
        description: description,
        creator: tx-sender,
        start-time: start-time,
        end-time: end-time,
        status: STATUS_PENDING,
        yes-votes: u0,
        no-votes: u0,
        total-votes: u0
      }
    )
    
    ;; Increment the proposal ID counter
    (var-set next-proposal-id (+ proposal-id u1))
    
    ;; Return the proposal ID
    (ok proposal-id)
  )
)

;; Function to cast a vote on a proposal
(define-public (cast-vote (proposal-id uint) (vote-option bool) (vote-amount uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) (err ERR_INVALID_PROPOSAL)))
      (current-time block-height)
    )
    ;; Check if the proposal is active
    (asserts! (>= current-time (get start-time proposal)) (err ERR_PROPOSAL_NOT_STARTED))
    (asserts! (<= current-time (get end-time proposal)) (err ERR_PROPOSAL_CLOSED))
    (asserts! (is-eq (get status proposal) STATUS_ACTIVE) (err ERR_PROPOSAL_CLOSED))
    
    ;; Check if the voter has already voted
    (asserts! (is-none (map-get? votes { proposal-id: proposal-id, voter: tx-sender })) (err ERR_ALREADY_VOTED))
    
    ;; TODO: In a real implementation, check if the voter has sufficient voting power
    ;; This would typically involve checking token balances or delegated voting rights
    
    ;; Record the vote
    (map-set votes
      { proposal-id: proposal-id, voter: tx-sender }
      {
        vote-option: vote-option,
        vote-amount: vote-amount,
        timestamp: current-time
      }
    )
    
    ;; Update the proposal vote counts
    (map-set proposals
      { proposal-id: proposal-id }
      (merge proposal {
        yes-votes: (if vote-option
                      (+ (get yes-votes proposal) vote-amount)
                      (get yes-votes proposal)),
        no-votes: (if vote-option
                     (get no-votes proposal)
                     (+ (get no-votes proposal) vote-amount)),
        total-votes: (+ (get total-votes proposal) vote-amount)
      })
    )
    
    (ok true)
  )
)

;; Function to count votes and update proposal status
(define-public (count-votes (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) (err ERR_INVALID_PROPOSAL)))
      (current-time block-height)
    )
    ;; Check if the proposal has ended
    (asserts! (> current-time (get end-time proposal)) (err ERR_PROPOSAL_NOT_STARTED))
    
    ;; Determine the new status based on votes
    (let
      (
        (yes-votes (get yes-votes proposal))
        (no-votes (get no-votes proposal))
        (new-status (if (> yes-votes no-votes) STATUS_APPROVED STATUS_REJECTED))
      )
      ;; Update the proposal status
      (map-set proposals
        { proposal-id: proposal-id }
        (merge proposal { status: new-status })
      )
      
      (ok new-status)
    )
  )
)

;; Function to get the current status of a proposal
(define-read-only (get-proposal-status (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) (err ERR_INVALID_PROPOSAL)))
      (current-time block-height)
    )
    ;; If the proposal is pending and the start time has passed, update to active
    (if (and (is-eq (get status proposal) STATUS_PENDING)
             (>= current-time (get start-time proposal)))
        (begin
          ;; Note: In read-only functions we can't modify state, so this is just for the return value
          (ok STATUS_ACTIVE)
        )
        ;; Otherwise return the current status
        (ok (get status proposal))
    )
  )
)

;; Function to get detailed information about a proposal
(define-read-only (get-proposal-details (proposal-id uint))
  (map-get? proposals { proposal-id: proposal-id })
)

;; Function to check if a principal has voted on a specific proposal
(define-read-only (has-voted (proposal-id uint) (voter principal))
  (is-some (map-get? votes { proposal-id: proposal-id, voter: voter }))
)

;; Function to get vote details for a specific voter on a proposal
(define-read-only (get-vote-details (proposal-id uint) (voter principal))
  (map-get? votes { proposal-id: proposal-id, voter: voter })
)

;; Function to activate a pending proposal (if it's time)
(define-public (activate-proposal (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) (err ERR_INVALID_PROPOSAL)))
      (current-time block-height)
    )
    ;; Check if the proposal is pending and start time has passed
    (asserts! (is-eq (get status proposal) STATUS_PENDING) (err ERR_INVALID_PROPOSAL))
    (asserts! (>= current-time (get start-time proposal)) (err ERR_PROPOSAL_NOT_STARTED))
    
    ;; Update the proposal status to active
    (map-set proposals
      { proposal-id: proposal-id }
      (merge proposal { status: STATUS_ACTIVE })
    )
    
    (ok true)
  )
)

;; Function to close a proposal early (only by creator)
(define-public (close-proposal (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) (err ERR_INVALID_PROPOSAL)))
    )
    ;; Check if the caller is the creator
    (asserts! (is-eq tx-sender (get creator proposal)) (err ERR_UNAUTHORIZED))
    
    ;; Update the proposal status to closed
    (map-set proposals
      { proposal-id: proposal-id }
      (merge proposal { status: STATUS_CLOSED })
    )
    
    (ok true)
  )
)