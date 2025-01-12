
;; title: proxy-management
;; version:
;; summary:
;; description:

;; Proxy Management Smart Contract
;; Implements functionality for shareholders to manage voting proxies

;; Data Maps
(define-map proxies
    { shareholder: principal }
    { proxy: (optional principal) })

(define-map proxy-reputation
    { proxy: principal }
    {
        total-votes: uint,
        successful-votes: uint,
        reputation-score: uint
    })

(define-map proxy-voting-history
    { proxy: principal, proposal-id: uint }
    { vote: (optional bool) })

;; Error Constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-PROXY (err u101))
(define-constant ERR-NOT-PROXY (err u102))
(define-constant ERR-INVALID-PROXY (err u103))

;; Public Functions

;; Add a proxy for the sender
(define-public (add-proxy (proxy-address principal))
    (let
        ((current-proxy (get proxy (default-to { proxy: none } (map-get? proxies { shareholder: tx-sender })))))
        (asserts! (is-none current-proxy) ERR-ALREADY-PROXY)
        (asserts! (is-valid-proxy proxy-address) ERR-INVALID-PROXY)
        (ok (map-set proxies
            { shareholder: tx-sender }
            { proxy: (some proxy-address) }))))

;; Remove the current proxy
(define-public (remove-proxy)
    (let
        ((current-proxy (get proxy (default-to { proxy: none } (map-get? proxies { shareholder: tx-sender })))))
        (asserts! (is-some current-proxy) ERR-NOT-PROXY)
        (ok (map-set proxies
            { shareholder: tx-sender }
            { proxy: none }))))

;; Record a vote by a proxy
(define-public (record-proxy-vote (proposal-id uint) (vote bool))
    (let
        ((proxy-rep (default-to
            { total-votes: u0, successful-votes: u0, reputation-score: u0 }
            (map-get? proxy-reputation { proxy: tx-sender }))))
        (begin
            (map-set proxy-voting-history
                { proxy: tx-sender, proposal-id: proposal-id }
                { vote: (some vote) })
            (map-set proxy-reputation
                { proxy: tx-sender }
                {
                    total-votes: (+ (get total-votes proxy-rep) u1),
                    successful-votes: (get successful-votes proxy-rep),
                    reputation-score: (calculate-reputation proxy-rep)
                })
            (ok true))))

;; Get proxy's voting history for a specific proposal
(define-public (get-proxy-vote (proxy-address principal) (proposal-id uint))
    (ok (get vote (default-to
        { vote: none }
        (map-get? proxy-voting-history { proxy: proxy-address, proposal-id: proposal-id })))))

;; Get proxy's reputation
(define-read-only (get-proxy-reputation (proxy-address principal))
    (default-to
        { total-votes: u0, successful-votes: u0, reputation-score: u0 }
        (map-get? proxy-reputation { proxy: proxy-address })))

;; Private Functions

;; Calculate reputation score based on voting history
(define-private (calculate-reputation (proxy-rep { total-votes: uint, successful-votes: uint, reputation-score: uint }))
    (if (> (get total-votes proxy-rep) u0)
        (/ (* (get successful-votes proxy-rep) u100) (get total-votes proxy-rep))
        u0))

;; Validate if an address can be a proxy
(define-private (is-valid-proxy (proxy-address principal))
    (let
        ((rep (get-proxy-reputation proxy-address)))
        (> (get reputation-score rep) u50)))