;; Voting Rights Transfer and Token Staking Smart Contract
;; This contract implements tokenized governance with delegation and staking

;; Define the governance token
(define-fungible-token governance-token)

;; Data maps to track various aspects of the voting system
(define-map token-balances principal uint)
(define-map delegated-to {owner: principal} {delegate: principal})
(define-map voting-power principal uint)
(define-map staked-tokens {staker: principal} {amount: uint, until-block: uint})
(define-map votes {proposal-id: uint} {voter: principal, vote: bool, weight: uint})
(define-map proposals uint {description: (string-utf8 256), deadline: uint, for-votes: uint, against-votes: uint, executed: bool})
(define-data-var proposal-count uint u0)

;; Error codes
(define-constant ERR-NOT-AUTHORIZED u1)
(define-constant ERR-ALREADY-VOTED u2)
(define-constant ERR-VOTING-CLOSED u3)
(define-constant ERR-INSUFFICIENT-BALANCE u4)
(define-constant ERR-ALREADY-EXECUTED u5)
(define-constant ERR-STAKE-LOCKED u6)

(define-constant contract-owner tx-sender)

;; Initialize the contract with initial token distribution
(define-public (initialize (recipient principal) (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) (err ERR-NOT-AUTHORIZED))
    (try! (ft-mint? governance-token amount recipient))
    (map-set token-balances recipient amount)
    (map-set voting-power recipient amount)
    (ok true)))

;; Transfer tokens to another address
(define-public (transfer (amount uint) (recipient principal))
  (let ((sender-balance (default-to u0 (map-get? token-balances tx-sender)))
        (recipient-balance (default-to u0 (map-get? token-balances recipient)))
        (sender-delegate (default-to {delegate: tx-sender} (map-get? delegated-to {owner: tx-sender})))
        (recipient-delegate (default-to {delegate: recipient} (map-get? delegated-to {owner: recipient}))))
    
    ;; Check if sender has enough tokens
    (asserts! (>= sender-balance amount) (err ERR-INSUFFICIENT-BALANCE))
    
    ;; Check if any tokens are staked
    (asserts! (is-none (map-get? staked-tokens {staker: tx-sender})) (err ERR-STAKE-LOCKED))
    
    ;; Update token balances
    (map-set token-balances tx-sender (- sender-balance amount))
    (map-set token-balances recipient (+ recipient-balance amount))
    
    ;; Update voting power for delegates
    (map-set voting-power (get delegate sender-delegate) 
             (- (default-to u0 (map-get? voting-power (get delegate sender-delegate))) amount))
    (map-set voting-power (get delegate recipient-delegate) 
             (+ (default-to u0 (map-get? voting-power (get delegate recipient-delegate))) amount))
    
    ;; Perform the token transfer
    (try! (ft-transfer? governance-token amount tx-sender recipient))
    (ok true)))

;; Delegate voting rights to another address
(define-public (delegate-to (delegate principal))
  (let ((current-delegate (default-to {delegate: tx-sender} (map-get? delegated-to {owner: tx-sender})))
        (owner-balance (default-to u0 (map-get? token-balances tx-sender))))
    
    ;; Update voting power for the old delegate
    (map-set voting-power (get delegate current-delegate) 
             (- (default-to u0 (map-get? voting-power (get delegate current-delegate))) owner-balance))
    
    ;; Update voting power for the new delegate
    (map-set voting-power delegate 
             (+ (default-to u0 (map-get? voting-power delegate)) owner-balance))
    
    ;; Set the new delegate
    (map-set delegated-to {owner: tx-sender} {delegate: delegate})
    (ok true)))

;; Create a new proposal
(define-public (create-proposal (description (string-utf8 256)) (deadline uint))
  (let ((proposal-id (var-get proposal-count)))
    ;; Ensure deadline is in the future
    (asserts! (> deadline stacks-block-height) (err u7))
    
    ;; Create the proposal
    (map-set proposals proposal-id {
      description: description,
      deadline: deadline,
      for-votes: u0,
      against-votes: u0,
      executed: false
    })
    
    ;; Increment proposal count
    (var-set proposal-count (+ proposal-id u1))
    (ok proposal-id)))

;; Vote on a proposal with staking
(define-public (vote-with-stake (proposal-id uint) (support bool) (stake-amount uint))
  (let ((proposal (unwrap! (map-get? proposals proposal-id) (err u8)))
        (voter-power (default-to u0 (map-get? voting-power tx-sender)))
        (voter-balance (default-to u0 (map-get? token-balances tx-sender))))
    
    ;; Check if voting is still open
    (asserts! (<= stacks-block-height (get deadline proposal)) (err ERR-VOTING-CLOSED))
    
    ;; Check if the proposal has already been executed
    (asserts! (not (get executed proposal)) (err ERR-ALREADY-EXECUTED))
    
    ;; Check if the voter has already voted
    (asserts! (is-none (map-get? votes {proposal-id: proposal-id})) (err ERR-ALREADY-VOTED))
    
    ;; Check if voter has enough tokens to stake
    (asserts! (>= voter-balance stake-amount) (err ERR-INSUFFICIENT-BALANCE))
    
    ;; Stake the tokens
    (map-set staked-tokens {staker: tx-sender} {
      amount: stake-amount,
      until-block: (+ (get deadline proposal) u100) ;; Lock for 100 blocks after voting ends
    })
    
    ;; Reduce available balance
    (map-set token-balances tx-sender (- voter-balance stake-amount))
    
    ;; Record the vote
    (map-set votes {proposal-id: proposal-id} {
      voter: tx-sender,
      vote: support,
      weight: voter-power
    })
    
    ;; Update vote tallies
    (if support
      (map-set proposals proposal-id (merge proposal {for-votes: (+ (get for-votes proposal) voter-power)}))
      (map-set proposals proposal-id (merge proposal {against-votes: (+ (get against-votes proposal) voter-power)}))
    )
    
    (ok true)))

;; Execute a proposal after voting has ended
(define-public (execute-proposal (proposal-id uint))
  (let ((proposal (unwrap! (map-get? proposals proposal-id) (err u8))))
    ;; Check if voting period has ended
    (asserts! (> stacks-block-height (get deadline proposal)) (err u9))
    
    ;; Check if the proposal has already been executed
    (asserts! (not (get executed proposal)) (err ERR-ALREADY-EXECUTED))
    
    ;; Check if the proposal passed (more for votes than against)
    (asserts! (> (get for-votes proposal) (get against-votes proposal)) (err u10))
    
    ;; Mark the proposal as executed
    (map-set proposals proposal-id (merge proposal {executed: true}))
    
    ;; Here you would typically call a function to implement the proposal
    ;; This is a placeholder for actual execution logic
    (ok true)))

;; Unstake tokens after the lock period
(define-public (unstake)
  (let ((stake (unwrap! (map-get? staked-tokens {staker: tx-sender}) (err u11)))
        (current-balance (default-to u0 (map-get? token-balances tx-sender))))
    
    ;; Check if the stake lock period has ended
    (asserts! (>= stacks-block-height (get until-block stake)) (err ERR-STAKE-LOCKED))
    
    ;; Return staked tokens to the user's balance
    (map-set token-balances tx-sender (+ current-balance (get amount stake)))
    
    ;; Clear the stake record
    (map-delete staked-tokens {staker: tx-sender})
    
    (ok true)))

;; Read-only function to get voting power
(define-read-only (get-voting-power (address principal))
  (default-to u0 (map-get? voting-power address)))

;; Read-only function to get token balance
(define-read-only (get-balance (address principal))
  (default-to u0 (map-get? token-balances address)))

;; Read-only function to get proposal details
(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals proposal-id))

;; Read-only function to check if tokens are staked
(define-read-only (get-stake (address principal))
  (map-get? staked-tokens {staker: address}))