;; Proxy Voting and Reporting Smart Contract
;; Tracks proxy voting behavior and maintains an audit trail of votes

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_PROPOSAL (err u101))
(define-constant ERR_INVALID_VOTE_AMOUNT (err u102))
(define-constant ERR_ALREADY_VOTED (err u103))
(define-constant ERR_VOTING_CLOSED (err u104))
(define-constant ERR_VOTING_OPEN (err u105))
(define-constant ERR_INVALID_PROXY (err u106))
(define-constant ERR_NO_VOTING_POWER (err u107))

;; Data Variables
(define-data-var proposal-counter uint u0)

;; Data Maps
;; Proposal details
(define-map proposals uint {
  title: (string-utf8 256),
  description: (string-utf8 1024),
  start-block-height: uint,
  end-block-height: uint,
  is-active: bool,
  results-announced: bool,
  votes-for: uint,
  votes-against: uint,
  votes-abstain: uint
})

;; Vote options
(define-data-var vote-options (list 3 (string-ascii 10)) (list "FOR" "AGAINST" "ABSTAIN"))

;; Track votes by proxy for each proposal
(define-map proxy-votes {proposal-id: uint, proxy: principal} {
  vote-option: (string-ascii 10),
  vote-amount: uint,
  block-height: uint,
  timestamp: uint
})

;; Track all proposals a proxy has voted on
(define-map proxy-voting-history principal (list 100 uint))

;; Track all proxies that have voted on a proposal
(define-map proposal-voters uint (list 100 principal))

;; Track delegators who authorized a proxy to vote on their behalf
(define-map vote-delegations {proposal-id: uint, proxy: principal} (list 100 {shareholder: principal, amount: uint}))

;; Functions

;; Create a new proposal
(define-public (create-proposal (title (string-utf8 256)) (description (string-utf8 1024)) (duration uint))
  (let ((proposal-id (var-get proposal-counter))
        (start-block stacks-block-height)
        (end-block duration))
    
    ;; Only contract owner can create proposals
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    
    ;; Store proposal details
    (map-set proposals proposal-id {
      title: title,
      description: description,
      start-block-height: stacks-block-height,
      end-block-height: end-block,
      is-active: true,
      results-announced: false,
      votes-for: u0,
      votes-against: u0,
      votes-abstain: u0
    })
    
    ;; Increment proposal counter
    (var-set proposal-counter (+ proposal-id u1))
    
    ;; Emit proposal creation event
    (print {
      event: "proposal-created",
      proposal-id: proposal-id,
      title: title,
      start-block: stacks-block-height,
      end-block: end-block
    })
    
    (ok proposal-id)
  )
)

;; Record a vote cast by a proxy
(define-public (record-proxy-vote (proposal-id uint) (vote-option (string-ascii 10)) (vote-amount uint) (delegators (list 100 {shareholder: principal, amount: uint})))
  (let (
    (proxy tx-sender)
    (proposal (unwrap! (map-get? proposals proposal-id) ERR_INVALID_PROPOSAL))
    (current-block stacks-block-height )
    (current-time stacks-block-height)
  )
    ;; Validate proposal is active
    (asserts! (get is-active proposal) ERR_VOTING_CLOSED)
    (asserts! (<= (get start-block-height proposal) current-block) ERR_INVALID_PROPOSAL)
    (asserts! (>= (get end-block-height proposal) current-block) ERR_VOTING_CLOSED)
    
    ;; Validate vote amount
    (asserts! (> vote-amount u0) ERR_INVALID_VOTE_AMOUNT)
    
    ;; Validate proxy hasn't already voted on this proposal
    (asserts! (is-none (map-get? proxy-votes {proposal-id: proposal-id, proxy: proxy})) ERR_ALREADY_VOTED)
    
    ;; Validate vote option is valid
    (asserts! (is-some (index-of (var-get vote-options) vote-option)) ERR_INVALID_PROPOSAL)
    
    ;; Record the vote
    (map-set proxy-votes {proposal-id: proposal-id, proxy: proxy} {
      vote-option: vote-option,
      vote-amount: vote-amount,
      block-height: current-block,
      timestamp: current-time
    })
    
    ;; Store delegators who authorized this vote
    (map-set vote-delegations {proposal-id: proposal-id, proxy: proxy} delegators)
    

    
    ;; Update proxy voting history
    (let ((history (default-to (list) (map-get? proxy-voting-history proxy))))
      (map-set proxy-voting-history proxy 
        (unwrap! (as-max-len? (append history proposal-id) u100) ERR_UNAUTHORIZED))
    )
    
    ;; Update proposal voters
    (let ((voters (default-to (list) (map-get? proposal-voters proposal-id))))
      (map-set proposal-voters proposal-id 
        (unwrap! (as-max-len? (append voters proxy) u100) ERR_UNAUTHORIZED))
    )
    
    ;; Emit vote recorded event
    (print {
      event: "proxy-vote-recorded",
      proposal-id: proposal-id,
      proxy: proxy,
      vote-option: vote-option,
      vote-amount: vote-amount,
      delegators-count: (len delegators)
    })
    
    (ok true)
  )
)


;; Announce vote results for a proposal
(define-public (announce-vote-results (proposal-id uint))
  (let ((proposal (unwrap! (map-get? proposals proposal-id) ERR_INVALID_PROPOSAL))
        (current-block stacks-block-height))
    
    ;; Only contract owner can announce results
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    
    ;; Ensure voting period has ended
    (asserts! (> current-block (get end-block-height proposal)) ERR_VOTING_OPEN)
    
    ;; Ensure results haven't been announced yet
    (asserts! (not (get results-announced proposal)) ERR_UNAUTHORIZED)
    
    ;; Update proposal to mark results as announced and close voting
    (map-set proposals proposal-id (merge proposal {
      is-active: false,
      results-announced: true
    }))
    
    ;; Calculate total votes
    (let (
      (votes-for (get votes-for proposal))
      (votes-against (get votes-against proposal))
      (votes-abstain (get votes-abstain proposal))
      (total-votes (+ (+ votes-for votes-against) votes-abstain))
    )
      ;; Emit results announcement event
      (print {
        event: "vote-results-announced",
        proposal-id: proposal-id,
        title: (get title proposal),
        votes-for: votes-for,
        votes-against: votes-against,
        votes-abstain: votes-abstain,
        total-votes: total-votes,
        result: (if (> votes-for votes-against) "PASSED" "REJECTED")
      })
      
      (ok {
        proposal-id: proposal-id,
        votes-for: votes-for,
        votes-against: votes-against,
        votes-abstain: votes-abstain,
        total-votes: total-votes,
        result: (if (> votes-for votes-against) "PASSED" "REJECTED")
      })
    )
  )
)

;; Get detailed vote information for a specific proposal
(define-read-only (get-proposal-details (proposal-id uint))
  (let ((proposal (unwrap! (map-get? proposals proposal-id) ERR_INVALID_PROPOSAL)))
    (ok {
      proposal-id: proposal-id,
      title: (get title proposal),
      description: (get description proposal),
      start-block-height: (get start-block-height proposal),
      end-block-height: (get end-block-height proposal),
      is-active: (get is-active proposal),
      results-announced: (get results-announced proposal),
      votes-for: (get votes-for proposal),
      votes-against: (get votes-against proposal),
      votes-abstain: (get votes-abstain proposal),
      total-votes: (+ (+ (get votes-for proposal) (get votes-against proposal)) (get votes-abstain proposal))
    })
  )
)

;; Get all proxies who voted on a specific proposal
(define-read-only (get-proposal-voters (proposal-id uint))
  (ok (default-to (list) (map-get? proposal-voters proposal-id)))
)

;; Get vote cast by a specific proxy for a specific proposal
(define-read-only (get-proxy-vote (proposal-id uint) (proxy-address principal))
  (ok (map-get? proxy-votes {proposal-id: proposal-id, proxy: proxy-address}))
)

;; Get delegators who authorized a proxy to vote on a proposal
(define-read-only (get-vote-delegators (proposal-id uint) (proxy-address principal))
  (ok (default-to (list) (map-get? vote-delegations {proposal-id: proposal-id, proxy: proxy-address})))
)


;; Helper function to filter active proposals
(define-private (filter-active-proposals (proposals-list (list 100 {
    proposal-id: uint,
    title: (string-utf8 256), 
    description: (string-utf8 1024), 
    start-block-height: uint, 
    end-block-height: uint,
    is-active: bool, 
    results-announced: bool,
    votes-for: uint, 
    votes-against: uint, 
    votes-abstain: uint,
    total-votes: uint
  })))
  (filter is-proposal-active proposals-list)
)

;; Helper function to check if a proposal is active
(define-private (is-proposal-active (proposal {
    proposal-id: uint,
    title: (string-utf8 256), 
    description: (string-utf8 1024), 
    start-block-height: uint, 
    end-block-height: uint,
    is-active: bool, 
    results-announced: bool,
    votes-for: uint, 
    votes-against: uint, 
    votes-abstain: uint,
    total-votes: uint
  }))
  (get is-active proposal)
)

;; Initialize contract
(begin
  (print "Proxy Voting and Reporting Contract Deployed")
  (print {
    contract-owner: CONTRACT_OWNER,
    vote-options: (var-get vote-options)
  })
)