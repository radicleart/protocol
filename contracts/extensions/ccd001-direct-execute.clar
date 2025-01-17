;; Title: CCD001 Direct Execute
;; Version: 1.0.0
;; Synopsis:
;; This extension allows a small number of very trusted principals to immediately
;; execute a proposal once a super majority is reached.
;; Description:
;; An extension meant for the bootstrapping period of a DAO. It temporarily gives
;; trusted principals the ability to perform a "direct execution"; meaning, they
;; can skip the voting process to immediately execute a proposal.
;; The Direct Execute extension is set with a sunset period of ~6 months from
;; deployment. Approvers, the parameters, and sunset period may be changed by
;; means of a future proposal.

;; TRAITS

(impl-trait .extension-trait.extension-trait)
(use-trait proposal-trait .proposal-trait.proposal-trait)

;; CONSTANTS

(define-constant ERR_UNAUTHORIZED (err u3000))
(define-constant ERR_NOT_APPROVER (err u3001))
(define-constant ERR_ALREADY_EXECUTED (err u3002))
(define-constant ERR_SUNSET_REACHED (err u3003))
(define-constant ERR_SUNSET_IN_PAST (err u3004))

;; DATA MAPS AND VARS

;; ~6 months from initial deployment
;; can be changed by future proposal
(define-data-var sunsetBlockHeight uint (+ block-height u25920))

;; signals required for an action
(define-data-var signalsRequired uint u1)

;; approver information
(define-map Approvers
  principal ;; address
  bool      ;; status
)
(define-map ApproverSignals
  {
    proposal: principal,
    approver: principal
  }
  bool ;; yes/no
)
(define-map SignalCount
  principal ;; proposal
  uint      ;; signals
)

;; Authorization Check

(define-public (is-dao-or-extension)
  (ok (asserts!
    (or
      (is-eq tx-sender .base-dao)
      (contract-call? .base-dao is-extension contract-caller))
    ERR_UNAUTHORIZED
  ))
)

;; Internal DAO functions

(define-public (set-sunset-block-height (height uint))
  (begin
    (try! (is-dao-or-extension))
    (asserts! (> height block-height) ERR_SUNSET_IN_PAST)
    (ok (var-set sunsetBlockHeight height))
  )
)

(define-public (set-approver (who principal) (status bool))
  (begin
    (try! (is-dao-or-extension))
    (ok (map-set Approvers who status))
  )
)

(define-public (set-signals-required (newRequirement uint))
  (begin
    (try! (is-dao-or-extension))
    (ok (var-set signalsRequired newRequirement))
  )
)

;; Public Functions

(define-read-only (is-approver (who principal))
  (default-to false (map-get? Approvers who))
)

(define-read-only (has-signalled (proposal principal) (who principal))
  (default-to false (map-get? ApproverSignals {proposal: proposal, approver: who}))
)

(define-read-only (get-signals-required)
  (var-get signalsRequired)
)

(define-read-only (get-signals (proposal principal))
  (default-to u0 (map-get? SignalCount proposal))
)

(define-public (direct-execute (proposal <proposal-trait>))
  (let
    (
      (proposalPrincipal (contract-of proposal))
      (signals (+ (get-signals proposalPrincipal) (if (has-signalled proposalPrincipal tx-sender) u0 u1)))
    )
    (asserts! (is-approver tx-sender) ERR_NOT_APPROVER)
    (asserts! (< block-height (var-get sunsetBlockHeight)) ERR_SUNSET_REACHED)
    (and (>= signals (var-get signalsRequired))
      (try! (contract-call? .base-dao execute proposal tx-sender))
    )
    (map-set ApproverSignals {proposal: proposalPrincipal, approver: tx-sender} true)
    (map-set SignalCount proposalPrincipal signals)
    (ok signals)
  )
)

;; Extension callback

(define-public (callback (sender principal) (memo (buff 34)))
  (ok true)
)
