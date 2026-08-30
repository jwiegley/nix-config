import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CONTRACTS = REPO / "test/ai/overlays"


def write_distribution(
    site: Path, name: str, version: str, requirements: tuple[str, ...] = ()
) -> None:
    normalized = re.sub(r"[-_.]+", "_", name)
    metadata = site / f"{normalized}-{version}.dist-info/METADATA"
    metadata.parent.mkdir(parents=True)
    lines = ["Metadata-Version: 2.3", f"Name: {name}", f"Version: {version}"]
    lines.extend(f"Requires-Dist: {requirement}" for requirement in requirements)
    metadata.write_text("\n".join(lines) + "\n\n")


def write_module(site: Path, name: str, body: str = "") -> None:
    path = site.joinpath(*name.split("."))
    if "." in name:
        path = path.with_suffix(".py")
        path.parent.mkdir(parents=True, exist_ok=True)
        for parent in path.parents:
            if parent == site:
                break
            (parent / "__init__.py").touch()
    else:
        path = path.with_suffix(".py")
    path.write_text(body)


class InstalledMetadataContractTests(unittest.TestCase):
    def run_contract(self, site: Path, name: str, *expected: str):
        env = os.environ.copy()
        env["PYTHONPATH"] = os.pathsep.join(
            part for part in (str(site), env.get("PYTHONPATH", "")) if part
        )
        return subprocess.run(
            [sys.executable, str(CONTRACTS / name), *expected],
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )

    def make_audio_site(self, site: Path) -> None:
        write_distribution(site, "mlx-audio", "0.5.0")
        write_module(site, "mlx_audio.version", '__version__ = "0.5.0"\n')

    def make_vlm_site(self, site: Path, mlx_requirement: str) -> None:
        requirements = (
            mlx_requirement,
            "transformers>=5.14.0",
            "miniaudio>=1.59",
            "tqdm>=4.66.2",
            "Pillow>=10.3.0",
            "requests>=2.31.0",
            "llguidance>=1.7.0",
            "mlx-audio>=0.4.3",
            "opencv-python>=4.12.0.88",
            "fastapi>=0.95.1",
            "python-multipart>=0.0.9",
            "starlette>=1.0.1",
            "uvicorn",
            "websockets>=14.0",
            "numpy",
        )
        versions = {
            "fastapi": "0.139.0",
            "llguidance": "1.7.0",
            "miniaudio": "1.61",
            "mlx": "0.32.1",
            "mlx-audio": "0.5.0",
            "numpy": "2.5.1",
            "opencv-python": "4.12.0.88",
            "Pillow": "12.3.0",
            "python-multipart": "0.0.22",
            "requests": "2.34.2",
            "starlette": "1.0.1",
            "tqdm": "4.68.4",
            "transformers": "5.15.0",
            "uvicorn": "0.51.0",
            "websockets": "14.2",
        }
        import_names = {
            "mlx-audio": "mlx_audio",
            "opencv-python": "cv2",
            "Pillow": "PIL",
            "python-multipart": "multipart",
        }
        for distribution, version in versions.items():
            write_distribution(site, distribution, version)
            module = import_names.get(distribution, distribution.replace("-", "_"))
            write_module(site, module)
        write_distribution(site, "mlx-vlm", "0.6.14", requirements)
        write_module(site, "mlx_vlm.version", '__version__ = "0.6.14"\n')

    def make_ddgs_site(
        self,
        site: Path,
        omlx_requirement: str = "ddgs==9.16.0",
        omlx_backends: tuple[object, ...] = (
            "brave",
            "duckduckgo",
            "grokipedia",
            "mojeek",
            "wikipedia",
            "yahoo",
        ),
        registered_backends: tuple[str, ...] = (
            "brave",
            "duckduckgo",
            "google",
            "grokipedia",
            "mojeek",
            "startpage",
            "wikipedia",
            "yahoo",
        ),
        ui_backends: tuple[str, ...] | None = None,
        ddgs_metadata_version: str = "9.16.0",
        ddgs_module_version: str = "9.16.0",
        ddgs_requirements: tuple[str, ...] = (
            "click>=8.1.8",
            "primp>=1.3.1",
            "lxml>=4.9.4",
        ),
    ) -> None:
        for distribution, version in {
            "click": "8.3.1",
            "fake-useragent": "2.2.0",
            "httpx": "0.28.1",
            "primp": "1.3.1",
            "lxml": "6.0.2",
        }.items():
            write_distribution(site, distribution, version)
            write_module(site, distribution.replace("-", "_"))
        write_module(
            site,
            "primp",
            "class Client:\n"
            "    def __init__(self, **kwargs):\n"
            "        self.kwargs = kwargs\n",
        )
        write_distribution(
            site, "ddgs", ddgs_metadata_version, ddgs_requirements
        )
        write_module(
            site,
            "ddgs.http_client",
            "import primp\n"
            "class HttpClient:\n"
            "    def __init__(self, proxy=None, timeout=10):\n"
            "        self.client = primp.Client(proxy=proxy, timeout=timeout)\n"
            "    def request(self, *_args, **_kwargs):\n"
            "        pass\n"
            "    def get(self, *_args, **_kwargs):\n"
            "        pass\n"
            "    def post(self, *_args, **_kwargs):\n"
            "        pass\n",
        )
        write_module(site, "ddgs.http_client2")
        write_module(
            site,
            "ddgs.ddgs",
            "class DDGS:\n"
            "    def __init__(self, timeout, proxy=None):\n"
            "        self.timeout = timeout\n"
            "        self.proxy = proxy\n"
            "    def __enter__(self):\n"
            "        return self\n"
            "    def __exit__(self, *_args):\n"
            "        return False\n"
            "    def text(self, query, *, max_results, backend):\n"
            "        return []\n",
        )
        write_module(
            site,
            "ddgs.engines",
            "ENGINES = {'text': {"
            + ", ".join(f"{backend!r}: object()" for backend in registered_backends)
            + "}}\n",
        )
        (site / "ddgs/__init__.py").write_text(
            f'from .ddgs import DDGS\n__version__ = "{ddgs_module_version}"\n'
        )
        write_module(
            site,
            "omlx.websearch",
            f"DDGS_TEXT_BACKENDS = {omlx_backends!r}\nHTTP_TIMEOUT_SECONDS = 20.0\n",
        )
        dashboard = site / "omlx/admin/static/js/dashboard.js"
        dashboard.parent.mkdir(parents=True)
        displayed_backends = omlx_backends if ui_backends is None else ui_backends
        dashboard.write_text(f"ddgsBackendList: {list(displayed_backends)!r},\n")
        write_distribution(site, "omlx", "0.6.2", (omlx_requirement,))

    def make_omlx_direct_reference_site(
        self,
        site: Path,
        *,
        embedding_requirement: str = "mlx-embeddings",
        missing_api: str | None = None,
    ) -> None:
        write_distribution(site, "mlx-embeddings", "0.1.0")
        write_distribution(site, "mlx-vlm", "0.6.14")
        write_distribution(
            site,
            "omlx",
            "0.6.2",
            (embedding_requirement, "mlx-vlm"),
        )
        write_module(
            site,
            "mlx_embeddings.utils",
            ""
            if missing_api == "mlx_embeddings.utils.prepare_inputs"
            else "def prepare_inputs():\n    pass\n",
        )
        embedding_exports = []
        if missing_api != "mlx_embeddings.load":
            embedding_exports.append("def load():\n    pass\n")
        if missing_api != "mlx_embeddings.generate":
            embedding_exports.append("def generate():\n    pass\n")
        (site / "mlx_embeddings/__init__.py").write_text("".join(embedding_exports))
        write_module(
            site,
            "mlx_vlm.tokenizer_utils",
            ""
            if missing_api == "mlx_vlm.tokenizer_utils.load_tokenizer"
            else "def load_tokenizer():\n    pass\n",
        )
        vlm_utils = (
            "class StoppingCriteria:\n    pass\n"
            "def get_model_path():\n    pass\n"
            "def load_model():\n    pass\n"
            "def load_processor():\n    pass\n"
        )
        if missing_api != "mlx_vlm.utils.load":
            vlm_utils += "def load():\n    pass\n"
        if missing_api != "mlx_vlm.utils.prepare_inputs":
            vlm_utils += "def prepare_inputs():\n    pass\n"
        write_module(
            site,
            "mlx_vlm.utils",
            vlm_utils,
        )
        write_module(
            site,
            "omlx.patches.mlx_vlm_qwen4_exp_compat",
            "from pathlib import Path\n"
            "from types import ModuleType\n"
            "import sys\n"
            "class ShardedEmbedding:\n"
            "    def __init__(self, *args):\n"
            "        pass\n"
            "    def parameters(self):\n"
            "        return {'weight_scale': object()}\n"
            "def apply_mlx_vlm_qwen4_exp_compat_patch():\n"
            "    module = ModuleType('mlx_vlm.models.qwen4_exp.language')\n"
            "    module.__file__ = str(Path(__file__).parent / 'vendor/qwen4_exp/language.py')\n"
            "    module.ShardedEmbedding = ShardedEmbedding\n"
            "    sys.modules[module.__name__] = module\n"
            "    return True\n"
            "def is_applied():\n"
            "    return 'mlx_vlm.models.qwen4_exp.language' in sys.modules\n",
        )

    def make_omlx_release_site(
        self,
        site: Path,
        *,
        installed_versions: dict[str, str] | None = None,
        direct_reference: bool = False,
    ) -> None:
        versions = {
            "mlx": "0.32.0",
            "mlx-lm": "0.31.3",
            "mlx-embeddings": "0.1.0",
            "mlx-vlm": "0.6.3",
            "mlx-audio": "0.4.3",
            "dflash-mlx": "0.1.10+omlx.7",
            "ddgs": "9.15.0",
            "transformers": "5.12.1",
            "numpy": "2.3.5",
            "librosa": "0.11.0",
            "sounddevice": "0.5.3",
        }
        versions.update(installed_versions or {})
        for name, version in versions.items():
            write_distribution(site, name, version)
        mlx_lm_requirement = (
            "mlx-lm @ git+https://example.invalid/mlx-lm"
            if direct_reference
            else "mlx-lm"
        )
        write_distribution(
            site,
            "omlx",
            "0.6.4",
            (
                "mlx==0.32.0",
                mlx_lm_requirement,
                "mlx-embeddings",
                "mlx-vlm",
                "dflash-mlx",
                "ddgs==9.15.0",
                "transformers>=5.12.1,<5.13",
                "numpy>=1.24.0,<2.4",
                'mlx-audio[tts,stt,sts]; extra == "audio"',
            ),
        )

    def test_mlx_audio_rejects_stale_catalog_version(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            site = Path(temp_dir)
            self.make_audio_site(site)
            accepted = self.run_contract(site, "mlx-audio-version-contract.py", "0.5.0")
            self.assertEqual(accepted.returncode, 0, accepted.stderr)

            rejected = self.run_contract(site, "mlx-audio-version-contract.py", "0.4.7")
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn(
                "catalog 0.4.7, metadata 0.5.0, module 0.5.0", rejected.stderr
            )

    def test_mlx_vlm_rejects_unsatisfied_installed_requirement(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            site = Path(temp_dir)
            self.make_vlm_site(site, "mlx>=0.32.0")
            accepted = self.run_contract(
                site, "mlx-vlm-dependency-contract.py", "0.6.14"
            )
            self.assertEqual(accepted.returncode, 0, accepted.stderr)

        with tempfile.TemporaryDirectory() as temp_dir:
            site = Path(temp_dir)
            self.make_vlm_site(site, "mlx>=99")
            rejected = self.run_contract(
                site, "mlx-vlm-dependency-contract.py", "0.6.14"
            )
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("mlx>=99 is not satisfied", rejected.stderr)

    def test_ddgs_rejects_runtime_dependency_drift(self):
        expected_requirements = (
            "click>=8.1.8",
            "primp>=1.3.1",
            "lxml>=4.9.4",
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            site = Path(temp_dir)
            self.make_ddgs_site(site)
            accepted = self.run_contract(
                site, "ddgs-dependency-contract.py", "9.16.0"
            )
            self.assertEqual(accepted.returncode, 0, accepted.stderr)

        with tempfile.TemporaryDirectory() as temp_dir:
            site = Path(temp_dir)
            self.make_ddgs_site(
                site,
                ddgs_metadata_version="9.15.0",
                ddgs_module_version="9.15.0",
                ddgs_requirements=(
                    "click>=8.1.8",
                    "fake-useragent>=2.2.0",
                    "httpx>=0.28.1",
                    "lxml>=4.9.4",
                    "primp>=1.3.1",
                ),
            )
            accepted = self.run_contract(
                site, "ddgs-dependency-contract.py", "9.15.0"
            )
            self.assertEqual(accepted.returncode, 0, accepted.stderr)

        drift_cases = [
            (
                f"missing-{name}",
                tuple(
                    requirement
                    for requirement in expected_requirements
                    if not requirement.startswith(f"{name}>")
                ),
            )
            for name in ("click", "lxml", "primp")
        ]
        drift_cases.append(
            ("extra-httpx", expected_requirements + ("httpx>=0.28.1",))
        )
        for label, requirements in drift_cases:
            with (
                self.subTest(label=label),
                tempfile.TemporaryDirectory() as temp_dir,
            ):
                site = Path(temp_dir)
                self.make_ddgs_site(site, ddgs_requirements=requirements)
                rejected = self.run_contract(
                    site, "ddgs-dependency-contract.py", "9.16.0"
                )
                self.assertNotEqual(rejected.returncode, 0)
                self.assertIn("DDGS runtime requirements mismatch", rejected.stderr)

        with tempfile.TemporaryDirectory() as temp_dir:
            site = Path(temp_dir)
            self.make_ddgs_site(
                site,
                ddgs_requirements=(
                    "click>=8.1.8",
                    "primp>=99",
                    "lxml>=4.9.4",
                ),
            )
            rejected = self.run_contract(
                site, "ddgs-dependency-contract.py", "9.16.0"
            )
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("primp>=99 is not satisfied", rejected.stderr)

    def test_omlx_rejects_loosened_ddgs_requirement(self):
        contract = "omlx-ddgs-version-contract.py"
        with tempfile.TemporaryDirectory() as temp_dir:
            site = Path(temp_dir)
            self.make_ddgs_site(site)
            accepted = self.run_contract(site, contract, "9.16.0")
            self.assertEqual(accepted.returncode, 0, accepted.stderr)

        for requirement in (
            "ddgs>=9.16.0",
            'ddgs==9.16.0; python_version > "0"',
            'ddgs==9.16.0; python_version < "0"',
            "ddgs[bogus]==9.16.0",
        ):
            with (
                self.subTest(requirement=requirement),
                tempfile.TemporaryDirectory() as temp_dir,
            ):
                site = Path(temp_dir)
                self.make_ddgs_site(site, omlx_requirement=requirement)
                rejected = self.run_contract(site, contract, "9.16.0")
                self.assertNotEqual(rejected.returncode, 0)
                self.assertIn("must require exactly ddgs==9.16.0", rejected.stderr)

        backend_cases = (
            (
                {
                    "omlx_backends": ("brave", "yandex"),
                    "registered_backends": ("brave",),
                },
                "unavailable DDGS text backends: ['yandex']",
            ),
            (
                {
                    "omlx_backends": ("brave",),
                    "registered_backends": ("brave",),
                    "ui_backends": ("brave", "yandex"),
                },
                "DDGS backend UI mismatch",
            ),
        )
        for kwargs, message in backend_cases:
            with (
                self.subTest(message=message),
                tempfile.TemporaryDirectory() as temp_dir,
            ):
                site = Path(temp_dir)
                self.make_ddgs_site(site, **kwargs)
                rejected = self.run_contract(site, contract, "9.16.0")
                self.assertNotEqual(rejected.returncode, 0)
                self.assertIn(message, rejected.stderr)

        with tempfile.TemporaryDirectory() as temp_dir:
            site = Path(temp_dir)
            self.make_ddgs_site(
                site,
                omlx_backends=("brave",),
                registered_backends=("brave",),
            )
            (site / "omlx/admin/static/js/dashboard.js").write_text(
                "ddgsBackendList: ['brave', injectedBackend],\n"
            )
            rejected = self.run_contract(site, contract, "9.16.0")
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("must contain one literal string array", rejected.stderr)

        for invalid_backends in ((), ("brave", "brave"), ("",), ("brave", 1)):
            with (
                self.subTest(invalid_backends=invalid_backends),
                tempfile.TemporaryDirectory() as temp_dir,
            ):
                site = Path(temp_dir)
                self.make_ddgs_site(site, omlx_backends=invalid_backends)
                rejected = self.run_contract(site, contract, "9.16.0")
                self.assertNotEqual(rejected.returncode, 0)
                self.assertIn("nonempty unique DDGS text backends", rejected.stderr)

        for dashboard_source in (
            "",
            "ddgsBackendList: ['brave'],\nddgsBackendList: ['brave'],\n",
        ):
            with (
                self.subTest(dashboard_source=dashboard_source),
                tempfile.TemporaryDirectory() as temp_dir,
            ):
                site = Path(temp_dir)
                self.make_ddgs_site(
                    site,
                    omlx_backends=("brave",),
                    registered_backends=("brave",),
                )
                (site / "omlx/admin/static/js/dashboard.js").write_text(
                    dashboard_source
                )
                rejected = self.run_contract(site, contract, "9.16.0")
                self.assertNotEqual(rejected.returncode, 0)
                self.assertIn("must contain one literal string array", rejected.stderr)

        for metadata_version, module_version in (
            ("9.15.0", "9.16.0"),
            ("9.16.0", "9.15.0"),
        ):
            with (
                self.subTest(
                    metadata_version=metadata_version,
                    module_version=module_version,
                ),
                tempfile.TemporaryDirectory() as temp_dir,
            ):
                site = Path(temp_dir)
                self.make_ddgs_site(
                    site,
                    ddgs_metadata_version=metadata_version,
                    ddgs_module_version=module_version,
                )
                rejected = self.run_contract(site, contract, "9.16.0")
                self.assertNotEqual(rejected.returncode, 0)
                self.assertIn("DDGS version mismatch", rejected.stderr)

        with tempfile.TemporaryDirectory() as temp_dir:
            site = Path(temp_dir)
            self.make_ddgs_site(site)
            (site / "ddgs/ddgs.py").write_text(
                "class DDGS:\n"
                "    def __init__(self, timeout):\n"
                "        self.timeout = timeout\n"
                "    def __enter__(self):\n"
                "        return self\n"
                "    def __exit__(self, *_args):\n"
                "        return False\n"
                "    def text(self):\n"
                "        return []\n"
            )
            rejected = self.run_contract(site, contract, "9.16.0")
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("text search call shape is incompatible", rejected.stderr)

        with tempfile.TemporaryDirectory() as temp_dir:
            site = Path(temp_dir)
            self.make_ddgs_site(site)
            (site / "ddgs/ddgs.py").write_text(
                "class DDGS:\n"
                "    def __init__(self, timeout):\n"
                "        self.timeout = timeout\n"
                "    def text(self, query, *, max_results, backend):\n"
                "        return []\n"
            )
            rejected = self.run_contract(site, contract, "9.16.0")
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("context manager protocol", rejected.stderr)

    def test_omlx_release_dependencies_reject_drift(self):
        contract = "omlx-release-dependency-contract.py"
        expected = (
            "mlx",
            "0.32.0",
            "mlx-embeddings",
            "0.1.0",
            "mlx-vlm",
            "0.6.3",
            "mlx-audio",
            "0.4.3",
            "dflash-mlx",
            "0.1.10+omlx.7",
            "ddgs",
            "9.15.0",
            "transformers",
            "5.12.1",
            "numpy",
            "2.3.5",
            "librosa",
            "0.11.0",
            "sounddevice",
            "0.5.3",
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            site = Path(temp_dir)
            self.make_omlx_release_site(site)
            accepted = self.run_contract(site, contract, *expected)
            self.assertEqual(accepted.returncode, 0, accepted.stderr)

        for name, version, diagnostic in (
            ("transformers", "5.15.0", "transformers<5.13,>=5.12.1"),
            ("numpy", "2.5.1", "numpy<2.4,>=1.24.0"),
        ):
            with (
                self.subTest(name=name),
                tempfile.TemporaryDirectory() as temp_dir,
            ):
                site = Path(temp_dir)
                self.make_omlx_release_site(
                    site, installed_versions={name: version}
                )
                rejected = self.run_contract(site, contract, *expected)
                self.assertNotEqual(rejected.returncode, 0)
                self.assertIn(diagnostic, rejected.stderr)

        with tempfile.TemporaryDirectory() as temp_dir:
            site = Path(temp_dir)
            self.make_omlx_release_site(site, direct_reference=True)
            rejected = self.run_contract(site, contract, *expected)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("direct reference survived", rejected.stderr)

        with tempfile.TemporaryDirectory() as temp_dir:
            site = Path(temp_dir)
            self.make_omlx_release_site(site)
            stale_expected = list(expected)
            stale_expected[1] = "0.32.2"
            rejected = self.run_contract(site, contract, *stale_expected)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("selected 0.32.2, installed 0.32.0", rejected.stderr)

    def test_omlx_direct_references_match_selected_versions_and_apis(self):
        contract = "omlx-direct-reference-contract.py"
        with tempfile.TemporaryDirectory() as temp_dir:
            site = Path(temp_dir)
            self.make_omlx_direct_reference_site(site)
            accepted = self.run_contract(site, contract, "0.1.0", "0.6.14")
            self.assertEqual(accepted.returncode, 0, accepted.stderr)

            for selected in (("0.0.9", "0.6.14"), ("0.1.0", "0.6.13")):
                with self.subTest(selected=selected):
                    rejected = self.run_contract(site, contract, *selected)
                    self.assertNotEqual(rejected.returncode, 0)
                    self.assertIn("version mismatch", rejected.stderr)

        with tempfile.TemporaryDirectory() as temp_dir:
            site = Path(temp_dir)
            self.make_omlx_direct_reference_site(
                site,
                embedding_requirement=(
                    "mlx-embeddings @ git+https://example.invalid/mlx-embeddings"
                ),
            )
            rejected = self.run_contract(site, contract, "0.1.0", "0.6.14")
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("exactly one unversioned mlx-embeddings", rejected.stderr)

        for missing_api, missing_symbol in (
            ("mlx_embeddings.load", "load"),
            ("mlx_embeddings.generate", "generate"),
            ("mlx_embeddings.utils.prepare_inputs", "prepare_inputs"),
            ("mlx_vlm.tokenizer_utils.load_tokenizer", "load_tokenizer"),
            ("mlx_vlm.utils.load", "load"),
            ("mlx_vlm.utils.prepare_inputs", "prepare_inputs"),
        ):
            with (
                self.subTest(missing_api=missing_api),
                tempfile.TemporaryDirectory() as temp_dir,
            ):
                site = Path(temp_dir)
                self.make_omlx_direct_reference_site(site, missing_api=missing_api)
                rejected = self.run_contract(site, contract, "0.1.0", "0.6.14")
                self.assertNotEqual(rejected.returncode, 0)
                self.assertIn(missing_symbol, rejected.stderr)

        with tempfile.TemporaryDirectory() as temp_dir:
            site = Path(temp_dir)
            self.make_omlx_direct_reference_site(site)
            (site / "mlx_embeddings/__init__.py").write_text(
                "load = None\ndef generate():\n    pass\n"
            )
            rejected = self.run_contract(site, contract, "0.1.0", "0.6.14")
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("oMLX dependency APIs are not callable", rejected.stderr)
            self.assertIn("mlx_embeddings.load", rejected.stderr)


if __name__ == "__main__":
    unittest.main()
