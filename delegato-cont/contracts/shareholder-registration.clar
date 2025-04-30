;; Title: Shareholder Registration and Identity Verification Contract
;; Version: 1.0
;; Summary: A decentralized contract that allows for shareholder registration, identity verification, and the issuance of shares. The contract supports functions for registering new shareholders, verifying their identity via KYC data, and minting share tokens to registered and verified shareholders.
;; Description: The Shareholder Registration and Identity Verification Contract provides a robust system for managing shareholder identities and share balances. This contract allows a user to register as a shareholder, undergo identity verification (KYC), and mint share tokens once their identity is verified. The contract ensures that only verified shareholders can hold shares and that only the contract owner (typically an admin) can perform verification and minting operations. The contract also tracks shareholder registration status, verification status, and share balances. It includes error handling to ensure that actions like registration, identity verification, and minting shares are properly gated by the appropriate conditions.


;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-not-owner (err u100))
(define-constant err-already-registered (err u101))
(define-constant err-not-verified (err u102))
(define-constant err-zero-shares (err u103))

;; Data Maps
(define-map Shareholders
    { address: principal }
    {
        is-registered: bool,
        is-verified: bool,
        share-balance: uint,
        kyc-hash: (optional (buff 32))
    }
)

;; Read-only functions
(define-read-only (get-shareholder-info (address principal))
    (default-to
        {
            is-registered: false,
            is-verified: false,
            share-balance: u0,
            kyc-hash: none
        }
        (map-get? Shareholders { address: address })
    )
)

(define-read-only (is-registered (address principal))
    (get is-registered (get-shareholder-info address))
)

(define-read-only (is-verified (address principal))
    (get is-verified (get-shareholder-info address))
)

(define-read-only (get-share-balance (address principal))
    (get share-balance (get-shareholder-info address))
)

;; Private functions
(define-private (is-contract-owner)
    (is-eq tx-sender contract-owner)
)

;; Public functions
(define-public (register-shareholder)
    (let (
        (sender tx-sender)
        (current-info (get-shareholder-info sender))
    )
    (asserts! (not (get is-registered current-info)) err-already-registered)
    (ok (map-set Shareholders
        { address: sender }
        {
            is-registered: true,
            is-verified: false,
            share-balance: u0,
            kyc-hash: none
        }
    )))
)

(define-public (verify-identity (address principal) (kyc-data (buff 32)))
    (begin
        (asserts! (is-contract-owner) err-not-owner)
        (asserts! (is-registered address) err-not-verified)
        (ok (map-set Shareholders
            { address: address }
            (merge (get-shareholder-info address)
                {
                    is-verified: true,
                    kyc-hash: (some kyc-data)
                }
            )
        ))
    )
)

(define-public (mint-shareholder-token (address principal) (share-amount uint))
    (begin
        (asserts! (is-contract-owner) err-not-owner)
        (asserts! (> share-amount u0) err-zero-shares)
        (asserts! (is-verified address) err-not-verified)
        (let (
            (current-info (get-shareholder-info address))
            (new-balance (+ (get share-balance current-info) share-amount))
        )
        (ok (map-set Shareholders
            { address: address }
            (merge current-info
                { share-balance: new-balance }
            )
        )))
    )
)