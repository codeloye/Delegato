;; Proxy Dispute Resolution Smart Contract
;; Handles dispute reporting and resolution for proxy voting systems

;; ===== CONSTANTS =====
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-DISPUTE-NOT-FOUND (err u101))
(define-constant ERR-DISPUTE-ALREADY-RESOLVED (err u102))
(define-constant ERR-INVALID-DISPUTE-STATUS (err u103))
(define-constant ERR-INSUFFICIENT-STAKE (err u104))
(define-constant ERR-ALREADY-REPORTED (err u105))
(define-constant ERR-SELF-REPORT (err u106))
(define-constant ERR-INVALID-PROPOSAL (err u107))

;; Minimum stake required to report a dispute (in microSTX)
(define-constant MIN-DISPUTE-STAKE u1000000) ;; 1 STX

;; Reward percentage for valid dispute reports (basis points)
(define-constant REWARD-PERCENTAGE u500) ;; 5%

;; ===== DATA VARIABLES =====
(define-data-var dispute-counter uint u0)
(define-data-var arbitrator principal CONTRACT-OWNER)

;; ===== DATA MAPS =====

;; Dispute information
(define-map disputes
    { dispute-id: uint }
    {
        reporter: principal,
        proxy-address: principal,
        proposal-id: uint,
        description: (string-utf8 500),
        stake-amount: uint,
        status: (string-ascii 20), ;; "pending", "resolved-valid", "resolved-invalid"
        resolution-reason: (string-utf8 500),
        created-at: uint,
        resolved-at: (optional uint),
        resolver: (optional principal)
    }
)

;; Track if a user has already reported a specific proxy for a specific proposal
(define-map dispute-reports
    { reporter: principal, proxy-address: principal, proposal-id: uint }
    { dispute-id: uint }
)

;; Arbitrator roles (multiple arbitrators can be added)
(define-map arbitrators
    { arbitrator: principal }
    { is-active: bool, assigned-disputes: uint }
)

;; Proxy reputation tracking
(define-map proxy-reputation
    { proxy-address: principal }
    { 
        total-disputes: uint,
        valid-disputes: uint,
        reputation-score: uint ;; Scale of 0-1000 (1000 = perfect)
    }
)

;; Dispute evidence storage
(define-map dispute-evidence
    { dispute-id: uint, evidence-index: uint }
    { 
        submitter: principal,
        evidence-hash: (buff 32), ;; IPFS hash or similar
        evidence-type: (string-ascii 50),
        submitted-at: uint
    }
)

;; ===== PUBLIC FUNCTIONS =====

;; Report a dispute against a proxy
(define-public (report-dispute 
    (proxy-address principal) 
    (proposal-id uint) 
    (description (string-utf8 500))
    (stake-amount uint))
    (let 
        (
            (dispute-id (+ (var-get dispute-counter) u1))
            (current-block stacks-block-height)
        )
        ;; Validation checks
        (asserts! (>= stake-amount MIN-DISPUTE-STAKE) ERR-INSUFFICIENT-STAKE)
        (asserts! (not (is-eq tx-sender proxy-address)) ERR-SELF-REPORT)
        (asserts! (is-none (map-get? dispute-reports 
            { reporter: tx-sender, proxy-address: proxy-address, proposal-id: proposal-id })) 
            ERR-ALREADY-REPORTED)
        
        ;; Transfer stake to contract
        (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
        
        ;; Create dispute record
        (map-set disputes
            { dispute-id: dispute-id }
            {
                reporter: tx-sender,
                proxy-address: proxy-address,
                proposal-id: proposal-id,
                description: description,
                stake-amount: stake-amount,
                status: "pending",
                resolution-reason: u"",
                created-at: current-block,
                resolved-at: none,
                resolver: none
            }
        )
        
        ;; Track the report
        (map-set dispute-reports
            { reporter: tx-sender, proxy-address: proxy-address, proposal-id: proposal-id }
            { dispute-id: dispute-id }
        )
        
        ;; Update proxy reputation (increment total disputes)
        ;; (try! (update-proxy-reputation proxy-address u1 u0))
        
        ;; Update counter
        (var-set dispute-counter dispute-id)
        
        ;; Emit event
        (print {
            event: "dispute-reported",
            dispute-id: dispute-id,
            reporter: tx-sender,
            proxy-address: proxy-address,
            proposal-id: proposal-id,
            stake-amount: stake-amount
        })
        
        (ok dispute-id)
    )
)

;; Resolve a dispute (only arbitrators)
(define-public (resolve-dispute 
    (dispute-id uint) 
    (is-valid bool) 
    (resolution-reason (string-utf8 500)))
    (let 
        (
            (dispute-data (unwrap! (map-get? disputes { dispute-id: dispute-id }) ERR-DISPUTE-NOT-FOUND))
            (current-block stacks-block-height)
        )
        ;; Check authorization
        (asserts! (or 
            (is-eq tx-sender (var-get arbitrator))
            (default-to false (get is-active (map-get? arbitrators { arbitrator: tx-sender }))))
            ERR-UNAUTHORIZED)
        
        ;; Check if dispute is still pending
        (asserts! (is-eq (get status dispute-data) "pending") ERR-DISPUTE-ALREADY-RESOLVED)
        
        ;; Update dispute record
        (begin
            (map-set disputes
                { dispute-id: dispute-id }
                (merge dispute-data {
                    status: (if is-valid "resolved-valid" "resolved-invalid"),
                    resolution-reason: resolution-reason,
                    resolved-at: (some current-block),
                    resolver: (some tx-sender)
                })
            )
            
            
            ;; Emit event
            (print {
                event: "dispute-resolved",
                dispute-id: dispute-id,
                is-valid: is-valid,
                resolver: tx-sender,
                resolution-reason: resolution-reason
            })
            
            (ok true)
        )
    )
)

;; Add evidence to a dispute
(define-public (add-evidence 
    (dispute-id uint) 
    (evidence-hash (buff 32)) 
    (evidence-type (string-ascii 50)))
    (let 
        (
            (dispute-data (unwrap! (map-get? disputes { dispute-id: dispute-id }) ERR-DISPUTE-NOT-FOUND))
            (evidence-index (get-evidence-count dispute-id))
        )
        ;; Check if dispute exists and is pending
        (asserts! (is-eq (get status dispute-data) "pending") ERR-DISPUTE-ALREADY-RESOLVED)
        
        ;; Store evidence
        (map-set dispute-evidence
            { dispute-id: dispute-id, evidence-index: evidence-index }
            {
                submitter: tx-sender,
                evidence-hash: evidence-hash,
                evidence-type: evidence-type,
                submitted-at: stacks-block-height
            }
        )
        
        ;; Emit event
        (print {
            event: "evidence-added",
            dispute-id: dispute-id,
            submitter: tx-sender,
            evidence-index: evidence-index,
            evidence-type: evidence-type
        })
        
        (ok evidence-index)
    )
)



;; Set main arbitrator (only contract owner)
(define-public (set-arbitrator (new-arbitrator principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set arbitrator new-arbitrator)
        (ok true)
    )
)

;; ===== PRIVATE FUNCTIONS =====

;; Handle valid dispute resolution
(define-private (handle-valid-dispute (dispute-data { reporter: principal, proxy-address: principal, proposal-id: uint, description: (string-utf8 500), stake-amount: uint, status: (string-ascii 20), resolution-reason: (string-utf8 500), created-at: uint, resolved-at: (optional uint), resolver: (optional principal) }))
    (let 
        (
            (stake (get stake-amount dispute-data))
            (reporter (get reporter dispute-data))
            (reward (/ (* stake REWARD-PERCENTAGE) u10000))
        )
        ;; Return stake plus reward to reporter
        (try! (as-contract (stx-transfer? (+ stake reward) tx-sender reporter)))
        (ok true)
    )
)

;; Handle invalid dispute resolution
(define-private (handle-invalid-dispute (dispute-data { reporter: principal, proxy-address: principal, proposal-id: uint, description: (string-utf8 500), stake-amount: uint, status: (string-ascii 20), resolution-reason: (string-utf8 500), created-at: uint, resolved-at: (optional uint), resolver: (optional principal) }))
    (let 
        (
            (stake (get stake-amount dispute-data))
        )
        ;; Stake remains in contract (could be distributed to treasury or burned)
        ;; For now, it stays in contract
        (ok true)
    )
)

;; Update proxy reputation
(define-private (update-proxy-reputation (proxy-address principal) (total-increment uint) (valid-increment uint))
    (let 
        (
            (current-rep (default-to 
                { total-disputes: u0, valid-disputes: u0, reputation-score: u1000 }
                (map-get? proxy-reputation { proxy-address: proxy-address })
            ))
            (new-total (+ (get total-disputes current-rep) total-increment))
            (new-valid (+ (get valid-disputes current-rep) valid-increment))
            (new-score (if (> new-total u0)
                (- u1000 (/ (* new-valid u1000) new-total))
                u1000
            ))
        )
        (map-set proxy-reputation
            { proxy-address: proxy-address }
            {
                total-disputes: new-total,
                valid-disputes: new-valid,
                reputation-score: new-score
            }
        )
        (ok true)
    )
)

;; Get evidence count for a dispute
(define-private (get-evidence-count (dispute-id uint))
    ;; Simple linear search checking each index
    (if (is-some (map-get? dispute-evidence { dispute-id: dispute-id, evidence-index: u0 }))
        (if (is-some (map-get? dispute-evidence { dispute-id: dispute-id, evidence-index: u1 }))
            (if (is-some (map-get? dispute-evidence { dispute-id: dispute-id, evidence-index: u2 }))
                (if (is-some (map-get? dispute-evidence { dispute-id: dispute-id, evidence-index: u3 }))
                    (if (is-some (map-get? dispute-evidence { dispute-id: dispute-id, evidence-index: u4 }))
                        u5 ;; If index 4 exists, return 5 (next available index)
                        u4)
                    u3)
                u2)
            u1)
        u0)
)

;; ===== READ-ONLY FUNCTIONS =====

;; Get dispute details
(define-read-only (get-dispute (dispute-id uint))
    (map-get? disputes { dispute-id: dispute-id })
)

;; Get proxy reputation
(define-read-only (get-proxy-reputation (proxy-address principal))
    (default-to 
        { total-disputes: u0, valid-disputes: u0, reputation-score: u1000 }
        (map-get? proxy-reputation { proxy-address: proxy-address })
    )
)

;; Check if user is arbitrator
(define-read-only (is-arbitrator (user principal))
    (or 
        (is-eq user (var-get arbitrator))
        (default-to false (get is-active (map-get? arbitrators { arbitrator: user })))
    )
)

;; Get dispute evidence
(define-read-only (get-evidence (dispute-id uint) (evidence-index uint))
    (map-get? dispute-evidence { dispute-id: dispute-id, evidence-index: evidence-index })
)

;; Get current dispute counter
(define-read-only (get-dispute-counter)
    (var-get dispute-counter)
)

;; Check if a dispute has been reported
(define-read-only (has-reported-dispute (reporter principal) (proxy-address principal) (proposal-id uint))
    (is-some (map-get? dispute-reports { reporter: reporter, proxy-address: proxy-address, proposal-id: proposal-id }))
)

;; Get contract balance
(define-read-only (get-contract-balance)
    (stx-get-balance (as-contract tx-sender))
)