#!/usr/bin/env python3

"""Bounded, safety-critical subset of the complete updater test suite.

The ordinary commit gate runs hermetic CLI, schema, transaction, and routing
checks. The low-frequency expensive tier runs the unfiltered suite, including
real Nix/hash work and the publication, signal, and rollback matrix.
"""

import runpy
import unittest
from pathlib import Path


TARGET = Path(__file__).with_name("update-overlay-test.py")
TARGET_MODULE = runpy.run_path(str(TARGET))

CLI_METHODS = (
    "test_catalog_selection_preserves_manual_direct_and_filtered_all",
    "test_retired_ai_nix_flags_are_rejected",
    "test_retired_overlay_options_and_unknown_ids_are_rejected",
)

INVENTORY_METHODS = (
    "test_catalog_and_cli_inventory_cover_all_update_targets",
    "test_catalog_github_release_preserves_native_tag_field",
    "test_catalog_github_tag_preserves_native_tag_field",
    "test_catalog_npm_update_rewrites_source_and_dependent_hash_atomically",
    "test_catalog_pypi_update_preserves_fetchpypi_arguments",
    "test_explicit_catalog_record_isolation_allows_selected_and_rolls_back_sibling",
    "test_fod_hash_parser_requires_the_injected_dummy_pair",
    "test_github_client_does_not_change_declared_selection_strategy",
    "test_native_hash_records_exception_and_fetchtree_failures",
    "test_native_hash_surfaces_sanitized_actionable_nix_failure",
    "test_native_hash_uses_locked_fetcher_and_normalizes_to_sri",
    "test_source_catalog_is_data_only_unique_and_consumed",
    "test_source_catalog_rejects_ambiguous_native_fetcher_shapes",
    "test_source_transaction_rolls_back_and_commit_preserves",
    "test_update_callers_preserve_target_context_with_underlying_detail",
)

INTEGRATION_METHODS = (
    "test_active_commands_have_one_repository_update_transaction",
    "test_overlay_manifests_are_explicit_and_inputs_do_not_leak_through_pkgs",
    "test_upgrade_projects_continues_and_returns_aggregate_failure",
    "test_root_inputs_do_not_reference_external_filesystems",
    "test_root_lock_closure_has_no_unfetchable_locators",
    "test_portable_lock_closure_has_no_unfetchable_locators",
    "test_closure_walk_descends_past_direct_inputs",
    "test_closure_walk_follows_follows_edges",
    "test_production_seams_have_no_undeclared_inline_source_coordinates",
    "test_inline_source_gate_flags_each_fetcher_kind",
    "test_inline_source_gate_exact_set_rejects_new_and_stale",
    "test_flake_input_coordinates_are_internal_or_declared",
    "test_root_consumes_portable_input_authority_transitively",
    "test_profile_symlinked_scripts_find_packaged_routing_library",
    "test_host_routing_table_covers_system_and_shared_consumers",
    "test_independent_ai_packages_are_owned_under_packages",
    "test_update_agents_routes_npm_lock_projection_without_lock_updates",
    "test_all_inputs_prepares_npm_locks_after_lock_sync_before_generic_update",
    "test_update_agents_routes_github_projection_without_lock_updates",
)


def _test_ids(suite):
    for test in suite:
        if isinstance(test, unittest.TestSuite):
            yield from _test_ids(test)
        else:
            yield test.id()


def load_tests(loader, _standard_tests, _pattern):
    suite = unittest.TestSuite()

    def add_methods(class_name, method_names):
        test_class = TARGET_MODULE.get(class_name)
        if not isinstance(test_class, type) or not issubclass(
            test_class, unittest.TestCase
        ):
            raise RuntimeError(f"essential updater test class is missing: {class_name}")
        for method_name in method_names:
            if not callable(getattr(test_class, method_name, None)):
                raise RuntimeError(
                    f"essential updater test is missing: {class_name}.{method_name}"
                )
            suite.addTest(test_class(method_name))

    add_methods("UpdateCliTests", CLI_METHODS)
    add_methods("UpdateInventoryTests", INVENTORY_METHODS)

    add_methods("IntegratedWorkflowTests", INTEGRATION_METHODS)

    ids = list(_test_ids(suite))
    if not ids or len(ids) != len(set(ids)):
        raise RuntimeError("essential updater test plan is empty or contains duplicates")
    full_classes = sorted(
        (
            value
            for value in TARGET_MODULE.values()
            if isinstance(value, type)
            and issubclass(value, unittest.TestCase)
            and value.__module__ == "<run_path>"
        ),
        key=lambda value: value.__name__,
    )
    full_suite = unittest.TestSuite(
        loader.loadTestsFromTestCase(test_class) for test_class in full_classes
    )
    full_ids = set(_test_ids(full_suite))
    if not set(ids) < full_ids:
        raise RuntimeError(
            "essential updater test plan must be a strict subset of the full suite"
        )
    return suite


if __name__ == "__main__":
    unittest.main()
