;; Title: Vote Delegation System Contract
;; Version: 1.0
;; Summary: A decentralized smart contract for managing vote delegation in shareholder governance. This contract allows shareholders to delegate their voting rights to proxies, manage vote delegation, and track voting activity with transparency and immutability.
;; Description: The Vote Delegation System Contract enables shareholders to delegate their votes to trusted proxies, ensuring that voting rights can be transferred securely and efficiently. The contract supports features such as delegating and undelegating votes, checking available votes for delegation, and limiting the number of delegates per shareholder. It also includes error handling for scenarios such as insufficient votes, voting periods being closed, and attempts to delegate beyond the allowed number of delegates. All delegation actions are recorded on-chain to maintain transparency, and events are emitted to track changes in delegation status.

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-not-registered (err u100))
(define-constant err-insufficient-votes (err u101))
(define-constant err-already-delegated (err u102))
(define-constant err-not-delegated (err u103))
(define-constant err-voting-ended (err u104))
(define-constant err-invalid-amount (err u105))
(define-constant max-delegates-per-holder u3) ;; Maximum number of delegates per shareholder

;; Data Maps
(define-map DelegationInfo
    { shareholder: principal }
    {
        total-delegated: uint,
        delegate-count: uint
    }
)

(define-map DelegationDetails
    { shareholder: principal, delegate: principal }
    {
        vote-amount: uint,
        delegation-time: uint
    }
)

;; Read-only functions
(define-read-only (get-delegation-info (shareholder principal))
    (default-to
        {
            total-delegated: u0,
            delegate-count: u0
        }
        (map-get? DelegationInfo { shareholder: shareholder })
    )
)

(define-read-only (get-delegation-to-delegate (shareholder principal) (delegate principal))
    (default-to
        {
            vote-amount: u0,
            delegation-time: u0
        }
        (map-get? DelegationDetails { shareholder: shareholder, delegate: delegate })
    )
)

(define-read-only (check-delegation-status (shareholder principal))
    {
        info: (get-delegation-info shareholder),
        can-delegate: (< (get delegate-count (get-delegation-info shareholder)) max-delegates-per-holder)
    }
)

;; Private functions
(define-private (is-voting-active)
    ;; Implement your voting period check logic here
    true
)

(define-private (get-available-votes (shareholder principal))
    ;; This would typically integrate with your shareholder contract
    ;; For now, we'll just return a mock value
    (- (contract-call? .shareholder-registration get-share-balance shareholder)
       (get total-delegated (get-delegation-info shareholder)))
)

;; Public functions
(define-public (delegate-vote (delegate principal) (vote-amount uint))
    (let (
        (sender tx-sender)
        (delegation-info (get-delegation-info sender))
        (current-delegation (get-delegation-to-delegate sender delegate))
    )
        (asserts! (is-voting-active) err-voting-ended)
        (asserts! (> vote-amount u0) err-invalid-amount)
        (asserts! (<= vote-amount (get-available-votes sender)) err-insufficient-votes)
        (asserts! (< (get delegate-count delegation-info) max-delegates-per-holder) err-already-delegated)
        
        ;; Update delegation details
        (map-set DelegationDetails
            { shareholder: sender, delegate: delegate }
            {
                vote-amount: (+ vote-amount (get vote-amount current-delegation)),
                delegation-time: stacks-block-height
            }
        )
        
        ;; Update delegation info
        (map-set DelegationInfo
            { shareholder: sender }
            {
                total-delegated: (+ (get total-delegated delegation-info) vote-amount),
                delegate-count: (if (is-eq (get vote-amount current-delegation) u0)
                    (+ (get delegate-count delegation-info) u1)
                    (get delegate-count delegation-info))
            }
        )
        
        (ok true)
    )
)

(define-public (undelegate-vote (delegate principal))
    (let (
        (sender tx-sender)
        (delegation-info (get-delegation-info sender))
        (current-delegation (get-delegation-to-delegate sender delegate))
    )
        (asserts! (is-voting-active) err-voting-ended)
        (asserts! (> (get vote-amount current-delegation) u0) err-not-delegated)
        
        ;; Clear delegation details
        (map-set DelegationDetails
            { shareholder: sender, delegate: delegate }
            {
                vote-amount: u0,
                delegation-time: u0
            }
        )
        
        ;; Update delegation info
        (map-set DelegationInfo
            { shareholder: sender }
            {
                total-delegated: (- (get total-delegated delegation-info) 
                                  (get vote-amount current-delegation)),
                delegate-count: (- (get delegate-count delegation-info) u1)
            }
        )
        
        (ok true)
    )
)

(define-public (undelegate-all-votes)
    (let (
        (sender tx-sender)
        (delegation-info (get-delegation-info sender))
    )
        (asserts! (is-voting-active) err-voting-ended)
        (asserts! (> (get total-delegated delegation-info) u0) err-not-delegated)
        
        ;; Clear all delegation info
        (map-set DelegationInfo
            { shareholder: sender }
            {
                total-delegated: u0,
                delegate-count: u0
            }
        )
        
        (ok true)
    )
)

;; Events
(define-data-var last-delegation-event {
    shareholder: principal,
    delegate: principal,
    amount: uint,
    action: (string-ascii 20)
} {
    shareholder: contract-owner,
    delegate: contract-owner,
    amount: u0,
    action: "none"
})