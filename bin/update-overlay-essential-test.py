#!/usr/bin/env python3

"""Bounded, safety-critical subset of the complete updater test suite.

The ordinary commit gate runs every parser and catalog/unit test plus the
bounded integration checks below.  The low-frequency expensive tier runs the
unfiltered ``bin/update-overlay-test.py`` suite, including its temporary-Git
publication, signal, and rollback matrix.
"""

import runpy
import unittest
from pathlib import Path


TARGET = Path(__file__).with_name("update-overlay-test.py")
TARGET_MODULE = runpy.run_path(str(TARGET))

COMPLETE_CLASSES = (
    "OverlayParserTests",
    "UpdateInventoryTests",
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
    for class_name in COMPLETE_CLASSES:
        test_class = TARGET_MODULE.get(class_name)
        if not isinstance(test_class, type) or not issubclass(
            test_class, unittest.TestCase
        ):
            raise RuntimeError(f"essential updater test class is missing: {class_name}")
        suite.addTests(loader.loadTestsFromTestCase(test_class))

    integration_class = TARGET_MODULE.get("IntegratedWorkflowTests")
    if not isinstance(integration_class, type) or not issubclass(
        integration_class, unittest.TestCase
    ):
        raise RuntimeError("essential updater integration class is missing")
    for method_name in INTEGRATION_METHODS:
        if not callable(getattr(integration_class, method_name, None)):
            raise RuntimeError(
                f"essential updater integration test is missing: {method_name}"
            )
        suite.addTest(integration_class(method_name))

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
