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
        self, site: Path, extras: set[str], omlx_requirement: str = "ddgs==9.14.4"
    ) -> None:
        requirements = (
            "click>=8.1.8",
            "primp>=1.2.3",
            "lxml>=4.9.4",
            f"httpx[{','.join(sorted(extras))}]>=0.28.1",
            "fake-useragent>=2.2.0",
        )
        for distribution, version in {
            "click": "8.3.1",
            "primp": "1.2.3",
            "lxml": "6.0.2",
            "httpx": "0.28.1",
            "fake-useragent": "2.2.0",
        }.items():
            write_distribution(site, distribution, version)
            module = distribution.replace("-", "_")
            if module != "httpx":
                write_module(site, module)
        write_module(
            site,
            "httpx",
            "class Client:\n"
            "    def __init__(self, **kwargs):\n"
            "        self.kwargs = kwargs\n"
            "    def close(self):\n"
            "        pass\n",
        )
        for module in ("brotli", "h2", "socksio"):
            write_module(site, module)
        write_distribution(site, "ddgs", "9.14.4", requirements)
        write_module(
            site,
            "ddgs.ddgs",
            "class DDGS:\n    def text(self):\n        return []\n",
        )
        (site / "ddgs/__init__.py").write_text(
            'from .ddgs import DDGS\n__version__ = "9.14.4"\n'
        )
        write_distribution(site, "omlx", "0.6.1", (omlx_requirement,))

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
            "0.6.1",
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
        (site / "mlx_embeddings/__init__.py").write_text(
            "".join(embedding_exports)
        )
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

    def test_ddgs_rejects_each_missing_httpx_extra(self):
        expected_extras = {"brotli", "http2", "socks"}
        with tempfile.TemporaryDirectory() as temp_dir:
            site = Path(temp_dir)
            self.make_ddgs_site(site, expected_extras)
            accepted = self.run_contract(site, "ddgs-dependency-contract.py", "9.14.4")
            self.assertEqual(accepted.returncode, 0, accepted.stderr)

        for missing in sorted(expected_extras):
            with (
                self.subTest(missing=missing),
                tempfile.TemporaryDirectory() as temp_dir,
            ):
                site = Path(temp_dir)
                self.make_ddgs_site(site, expected_extras - {missing})
                rejected = self.run_contract(
                    site, "ddgs-dependency-contract.py", "9.14.4"
                )
                self.assertNotEqual(rejected.returncode, 0)
                self.assertIn("DDGS HTTPX extras mismatch", rejected.stderr)

    def test_omlx_rejects_loosened_ddgs_requirement(self):
        extras = {"brotli", "http2", "socks"}
        with tempfile.TemporaryDirectory() as temp_dir:
            site = Path(temp_dir)
            self.make_ddgs_site(site, extras)
            accepted = self.run_contract(
                site, "omlx-ddgs-version-contract.py", "9.14.4"
            )
            self.assertEqual(accepted.returncode, 0, accepted.stderr)

        with tempfile.TemporaryDirectory() as temp_dir:
            site = Path(temp_dir)
            self.make_ddgs_site(site, extras, "ddgs>=9.14.4")
            rejected = self.run_contract(
                site, "omlx-ddgs-version-contract.py", "9.14.4"
            )
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("must require exactly ddgs==9.14.4", rejected.stderr)

        with tempfile.TemporaryDirectory() as temp_dir:
            site = Path(temp_dir)
            self.make_ddgs_site(site, extras, 'ddgs==9.14.4; python_version < "0"')
            rejected = self.run_contract(
                site, "omlx-ddgs-version-contract.py", "9.14.4"
            )
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("must require exactly ddgs==9.14.4", rejected.stderr)

        with tempfile.TemporaryDirectory() as temp_dir:
            site = Path(temp_dir)
            self.make_ddgs_site(site, extras, "ddgs[bogus]==9.14.4")
            rejected = self.run_contract(
                site, "omlx-ddgs-version-contract.py", "9.14.4"
            )
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("must require exactly ddgs==9.14.4", rejected.stderr)

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
