# iOS bug batch P6: local verification

Verified iOS source `5d0e6da1`, evidence commit `127b9a43`; OPS-Web source `2a7f6ff3d`, integrated into local main. **159 iOS tests passed, zero failures or skips; 30 disposable PostgreSQL assertions passed.**

The iOS result, source hash manifest and scope details are retained in `ops-ios/docs/artifacts/ios-bugs-p6-20260914/`. Runtime bundle: `/private/tmp/ops-ios-bugs-p6/combined-green-3.xcresult`. SQL output: `/private/tmp/ops-project-reopen-proof.utglAj/sql.log`. Configuration: iPhone 17 simulator, iOS 26.5, SDK 27.0. Original archived-scheduling regression failed before the fix and passes in the final combined run.

Reopening archived jobs uses immutable receipt-backed commands with dependent task writes. Both central outbound paths and permanent inbound failures now produce scoped automatic bug reports. Chapters 03, 04, 06 and 10 describe the contracts and limitations.

Migration `20260914210950_project_task_reopen_receipts.sql` is mirrored in `migrations/pending/`; its source and mirror were compared byte-for-byte. Final live schema read showed the receipt table and RPC absent. Production migration, phone distribution and customer acceptance remain pending. No live bug rows were closed.
