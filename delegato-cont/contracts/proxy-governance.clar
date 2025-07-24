;; Proxy Voting Platform Governance Contract
;; Handles penalties for malicious behavior and platform governance

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_PROXY (err u101))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u102))
(define-constant ERR_PROPOSAL_EXPIRED (err u103))
(define-constant ERR_ALREADY_VOTED (err u104))
(define-constant ERR_INSUFFICIENT_TOKENS (err u105))
(define-constant ERR_PROPOSAL_NOT_APPROVED (err u106))
(define-constant ERR_ALREADY_PENALIZED (err u107))
(define-constant ERR_INVALID_PENALTY (err u108))
(define-constant ERR_PROPOSAL_STILL_ACTIVE (err u109))
(define-constant ERR_ALREADY_EXECUTED (err u110))

;; Governance parameters
(define-constant PENALTY_AMOUNT u1000) ;; Base penalty amount
(define-constant VOTING_PERIOD u1440) ;; 24 hours in blocks (assuming 1 min/block)
(define-constant APPROVAL_THRESHOLD u6667) ;; 66.67% approval needed (out of 10000)
(define-constant MIN_VOTING_POWER u100) ;; Minimum tokens to vote

;; Data Variables
(define-data-var proposal-counter uint u0)
(define-data-var total-governance-tokens uint u1000000)

;; Data Maps
;; Proxy reputation and penalty tracking
(define-map proxy-penalties 
    principal 
    {
        total-penalties: uint,
        penalty-count: uint,
        is-suspended: bool,
        last-penalty-block: uint
    }
)

;; Governance proposals
(define-map platform-proposals
    uint
    {
        proposer: principal,
        title: (string-ascii 100),
        description: (string-ascii 500),
        proposal-type: (string-ascii 50),
        start-block: uint,
        end-block: uint,
        votes-for: uint,
        votes-against: uint,
        is-approved: bool,
        is-executed: bool
    }
)

;; Voting records for proposals
(define-map proposal-votes
    {proposal-id: uint, voter: principal}
    {vote-power: uint, vote-choice: bool} ;; true = for, false = against
)

;; Governance token balances
(define-map governance-tokens principal uint)

;; Authorized governance roles
(define-map governance-roles principal bool)

;; Malicious behavior reports
(define-map malicious-reports
    {proxy: principal, reporter: principal, report-block: uint}
    {
        report-type: (string-ascii 50),
        evidence-hash: (buff 32),
        is-verified: bool,
        penalty-applied: bool
    }
)

;; Private Functions
;; Calculate penalty amount based on severity and history
(define-private (calculate-penalty-amount (proxy principal) (severity uint))
    (let (
        (penalty-history (default-to 
            {total-penalties: u0, penalty-count: u0, is-suspended: false, last-penalty-block: u0}
            (map-get? proxy-penalties proxy)
        ))
        (base-penalty (* PENALTY_AMOUNT severity))
        (multiplier (+ u1 (get penalty-count penalty-history)))
    )
    (* base-penalty multiplier))
)

;; Check if proposal is in voting period
(define-private (is-proposal-active (proposal-id uint))
    (match (map-get? platform-proposals proposal-id)
        proposal (and 
            (>= stacks-block-height (get start-block proposal))
            (<= stacks-block-height (get end-block proposal))
        )
        false
    )
)

;; Calculate voting result
(define-private (calculate-approval-rate (votes-for uint) (votes-against uint))
    (let ((total-votes (+ votes-for votes-against)))
        (if (> total-votes u0)
            (/ (* votes-for u10000) total-votes)
            u0
        )
    )
)

;; Public Functions
;; Initialize governance tokens for an address
(define-public (initialize-governance-tokens (recipient principal) (amount uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-set governance-tokens recipient amount)
        (ok amount)
    )
)

;; Grant governance role
(define-public (grant-governance-role (address principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-set governance-roles address true)
        (ok true)
    )
)

;; Report malicious behavior
(define-public (report-malicious-behavior 
    (proxy principal) 
    (report-type (string-ascii 50))
    (evidence-hash (buff 32)))
    (let (
        (reporter tx-sender)
        (report-key {proxy: proxy, reporter: reporter, report-block: stacks-block-height})
    )
        (asserts! (> (get-governance-token-balance reporter) MIN_VOTING_POWER) ERR_INSUFFICIENT_TOKENS)
        (map-set malicious-reports report-key {
            report-type: report-type,
            evidence-hash: evidence-hash,
            is-verified: false,
            penalty-applied: false
        })
        (ok report-key)
    )
)

;; Penalize malicious voting (can be called by governance role holders)
(define-public (penalize-malicious-voting (proxy-address principal) (severity uint))
    (let (
        (current-penalties (default-to 
            {total-penalties: u0, penalty-count: u0, is-suspended: false, last-penalty-block: u0}
            (map-get? proxy-penalties proxy-address)
        ))
        (penalty-amount (calculate-penalty-amount proxy-address severity))
        (new-penalty-count (+ (get penalty-count current-penalties) u1))
        (should-suspend (>= new-penalty-count u3)) ;; Suspend after 3 penalties
    )
        (asserts! (default-to false (map-get? governance-roles tx-sender)) ERR_UNAUTHORIZED)
        (asserts! (<= severity u5) ERR_INVALID_PENALTY) ;; Max severity level 5
        
        ;; Update penalty record
        (map-set proxy-penalties proxy-address {
            total-penalties: (+ (get total-penalties current-penalties) penalty-amount),
            penalty-count: new-penalty-count,
            is-suspended: should-suspend,
            last-penalty-block: stacks-block-height
        })
        
        (ok {
            penalty-amount: penalty-amount,
            total-penalties: (+ (get total-penalties current-penalties) penalty-amount),
            is-suspended: should-suspend
        })
    )
)

;; Create a platform governance proposal
(define-public (create-platform-proposal
    (title (string-ascii 100))
    (description (string-ascii 500))
    (proposal-type (string-ascii 50)))
    (let (
        (proposal-id (+ (var-get proposal-counter) u1))
        (proposer tx-sender)
        (start-block stacks-block-height)
        (end-block (+ stacks-block-height VOTING_PERIOD))
    )
        (asserts! (>= (get-governance-token-balance proposer) MIN_VOTING_POWER) ERR_INSUFFICIENT_TOKENS)
        
        (map-set platform-proposals proposal-id {
            proposer: proposer,
            title: title,
            description: description,
            proposal-type: proposal-type,
            start-block: start-block,
            end-block: end-block,
            votes-for: u0,
            votes-against: u0,
            is-approved: false,
            is-executed: false
        })
        
        (var-set proposal-counter proposal-id)
        (ok proposal-id)
    )
)

;; Vote on platform changes
(define-public (vote-on-platform-changes (proposal-id uint) (vote-choice bool))
    (let (
        (voter tx-sender)
        (vote-power (get-governance-token-balance voter))
        (vote-key {proposal-id: proposal-id, voter: voter})
    )
        (asserts! (is-proposal-active proposal-id) ERR_PROPOSAL_EXPIRED)
        (asserts! (>= vote-power MIN_VOTING_POWER) ERR_INSUFFICIENT_TOKENS)
        (asserts! (is-none (map-get? proposal-votes vote-key)) ERR_ALREADY_VOTED)
        
        (match (map-get? platform-proposals proposal-id)
            proposal (begin
                ;; Record the vote
                (map-set proposal-votes vote-key {
                    vote-power: vote-power,
                    vote-choice: vote-choice
                })
                
                ;; Update proposal vote counts
                (map-set platform-proposals proposal-id
                    (if vote-choice
                        (merge proposal {votes-for: (+ (get votes-for proposal) vote-power)})
                        (merge proposal {votes-against: (+ (get votes-against proposal) vote-power)})
                    )
                )
                
                (ok {proposal-id: proposal-id, vote-power: vote-power, vote-choice: vote-choice})
            )
            ERR_PROPOSAL_NOT_FOUND
        )
    )
)

;; Finalize and approve platform changes
(define-public (approve-platform-changes (proposal-id uint))
    (match (map-get? platform-proposals proposal-id)
        proposal (let (
            (approval-rate (calculate-approval-rate 
                (get votes-for proposal) 
                (get votes-against proposal)
            ))
            (is-approved (>= approval-rate APPROVAL_THRESHOLD))
        )
            (asserts! (> stacks-block-height (get end-block proposal)) ERR_PROPOSAL_STILL_ACTIVE)
            (asserts! (not (get is-approved proposal)) ERR_PROPOSAL_NOT_APPROVED)
            
            (map-set platform-proposals proposal-id
                (merge proposal {is-approved: is-approved})
            )
            
            (ok {
                proposal-id: proposal-id,
                is-approved: is-approved,
                approval-rate: approval-rate,
                votes-for: (get votes-for proposal),
                votes-against: (get votes-against proposal)
            })
        )
        ERR_PROPOSAL_NOT_FOUND
    )
)

;; Execute approved platform changes
(define-public (execute-platform-changes (proposal-id uint))
    (match (map-get? platform-proposals proposal-id)
        proposal (begin
            (asserts! (get is-approved proposal) ERR_PROPOSAL_NOT_APPROVED)
            (asserts! (not (get is-executed proposal)) ERR_ALREADY_EXECUTED)
            
            ;; Mark as executed
            (map-set platform-proposals proposal-id
                (merge proposal {is-executed: true})
            )
            
            ;; Here you would implement the actual changes based on proposal-type
            ;; This is a placeholder for the actual execution logic
            
            (ok proposal-id)
        )
        ERR_PROPOSAL_NOT_FOUND
    )
)

;; Read-only Functions
;; Get governance token balance
(define-read-only (get-governance-token-balance (address principal))
    (default-to u0 (map-get? governance-tokens address))
)

;; Get proxy penalty information
(define-read-only (get-proxy-penalties (proxy principal))
    (map-get? proxy-penalties proxy)
)

;; Get proposal information
(define-read-only (get-proposal-info (proposal-id uint))
    (map-get? platform-proposals proposal-id)
)

;; Get vote information
(define-read-only (get-vote-info (proposal-id uint) (voter principal))
    (map-get? proposal-votes {proposal-id: proposal-id, voter: voter})
)

;; Check if address has governance role
(define-read-only (is-governance-role (address principal))
    (default-to false (map-get? governance-roles address))
)

;; Get malicious behavior report
(define-read-only (get-malicious-report (proxy principal) (reporter principal) (report-block uint))
    (map-get? malicious-reports {proxy: proxy, reporter: reporter, report-block: report-block})
)

;; Check if proxy is suspended
(define-read-only (is-proxy-suspended (proxy principal))
    (match (map-get? proxy-penalties proxy)
        penalties (get is-suspended penalties)
        false
    )
)

;; Get current proposal counter
(define-read-only (get-proposal-counter)
    (var-get proposal-counter)
)

;; Get governance parameters
(define-read-only (get-governance-params)
    {
        penalty-amount: PENALTY_AMOUNT,
        voting-period: VOTING_PERIOD,
        approval-threshold: APPROVAL_THRESHOLD,
        min-voting-power: MIN_VOTING_POWER
    }
)