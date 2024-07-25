#
# METADATA
# title: OML checks
#
package policy.dataset

import rego.v1

import data.lib

# METADATA
# title: Training dataset comes from permitted sources
# description: >-
#   Verify the dataset used during model training comes from a known set of trusted sources. The
#   list of permitted sources can be customized by setting the `allowed_dataset_prefixes` list in
#   the rule data.
# custom:
#   short_name: permitted
#   failure_msg: "%s"
#
deny contains result if {
    some error in _errors
	result := lib.result_helper(rego.metadata.chain(), [error])
}

_errors contains error if {
    count(lib.results_named(_result_name)) == 0
    error := sprintf("No results named %q found", [_result_name])
}

_errors contains error if {
    count(lib.rule_data(_rule_data_key)) == 0
    error := sprintf("Rule data %q not provided", [_rule_data_key])
}

_errors contains error if {
    some result in lib.results_named(_result_name)
    url := result.value
    matches := [prefix |
        some prefix in lib.rule_data(_rule_data_key)
        startswith(url, prefix)
    ]
    count(matches) == 0
    error := sprintf("Dataset URL %q is not allowed", [url])
}

_result_name = "DATASET_URL"
_rule_data_key = "allowed_dataset_prefixes"
