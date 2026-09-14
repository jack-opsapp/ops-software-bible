# Crew expense corrections — integrated local proof

Bug `c381520d-84fa-40ea-ba66-67de14c717ce`. Verified iOS source `3353ecce`, evidence `95bfaf20`; OPS-Web source `134be2424`. Both are on local main. The pending migration and feature remain unreleased.

## Results

- 115 iOS tests passed with zero failures/skips, including 27 correction tests and existing expense approval, buckets, notification, submission, receipt-image and feedback coverage.
- 69 correction PostgreSQL assertions, seven real concurrent-session checks, 123 existing P5 accounting assertions with P7 installed, and two migration-safety rejection checks passed. Exact migration reapplication passed.
- Root inspected three exported images of the actual crew-history component: long names/amounts/tax/allocations at 375 and 390 points, plus omitted optional note. Values wrap and remain readable. No physical-phone financial interaction was performed.

Canonical iOS evidence: `ops-ios/docs/artifacts/ios-bugs-p7-20260914/`, containing verification text, machine-readable summary, exact source hashes and screenshots. Retained result `/private/tmp/ops-ios-bugs-p7/focused-2.xcresult`; log `/private/tmp/ops-ios-bugs-p7/focused-2.log`. Independent server logs `/private/tmp/ops-expense-correction-proof.K8C2GU`.

## Contract and release

Chapters 03/04/09 document private receipt/pending custody, exact reviewer command and immutable crew feedback. The command returns an eligible unapproved expense for crew resubmission without approving, paying or posting it. Identical replay returns the original receipt; an independent current-state read prevents historical snapshots from replacing newer crew work.

Pending migration `20260914214748_expense_admin_correction_review.sql` source and Bible mirror are byte-identical: SHA256 `f5a6d66815c8e9468817fc28d24a5fe1d7caa68dcb671b3b379a1ad227b5f015`. Install the separately approved P5 expense decision authority, accounting lifecycle and payroll compatibility stack first. Existing function body drift is rejected. Final live read found the correction RPC, history RPC and receipt table absent. No live bug row was closed; no production migration, provider write, push, phone install or App Store release occurred.

At the user's urgent cleanup boundary, all test activity stopped after success. Root exported the required evidence before releasing the P5 package cache, P6 DerivedData and simulator0510A40A-DBCA-45E2-A1ED-6E29C52C5F46 to the cleanup owner. Source, result bundles and proof remain preserved. Restoring regenerable build resources may be necessary for a later run.
