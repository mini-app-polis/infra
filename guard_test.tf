# Temporary: exists only to prove the destroy guard. terraform_data lives in
# state alone and touches nothing in AWS. Removed by the next pull request,
# which the guard must refuse until
# the pull request is labelled allow-destroy.
resource "terraform_data" "guard_test" {}
