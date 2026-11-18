"""Kiểm tra các ràng buộc triển khai Backend mà không cần cluster hoặc secret."""
import json
from pathlib import Path
import re
import shutil
import subprocess
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / "kubernetes" / "backend"
TARGETS = ("base", "overlays/staging", "overlays/staging-rwx",
           "dependencies/staging", "monitoring")


class UniqueLoader(yaml.SafeLoader):
    pass


def unique_mapping(loader, node, deep=False):
    result = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in result:
            raise ValueError(f"Khóa YAML trùng: {key}")
        result[key] = loader.construct_object(value_node, deep=deep)
    return result


UniqueLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, unique_mapping,
)


def render(target):
    result = subprocess.run(
        ["kubectl", "kustomize", str(BACKEND / target)],
        check=True, capture_output=True, encoding="utf-8",
    )
    return list(yaml.load_all(result.stdout, Loader=UniqueLoader))


def pod_spec(resource):
    if resource["kind"] in ("Deployment", "StatefulSet", "Job"):
        return resource["spec"]["template"]["spec"]
    return None


class BackendManifestTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rendered = {target: render(target) for target in TARGETS}

    def test_yaml_has_no_duplicate_keys(self):
        for path in BACKEND.rglob("*.yaml"):
            with self.subTest(path=path):
                list(yaml.load_all(path.read_text(encoding="utf-8"), Loader=UniqueLoader))

    def test_rendered_resources_are_unique_and_namespaced(self):
        for target, resources in self.rendered.items():
            seen = set()
            for item in resources:
                key = (item["kind"], item["metadata"]["name"])
                self.assertNotIn(key, seen, (target, key))
                seen.add(key)
                if target != "base" and item["kind"] != "Namespace":
                    self.assertEqual(item["metadata"]["namespace"], "ai-recognition-staging")

    def test_no_credentials_are_embedded_in_deployable_resources(self):
        for resources in self.rendered.values():
            for item in resources:
                self.assertNotEqual(item["kind"], "Secret")
                text = json.dumps(item)
                self.assertNotRegex(text, r"postgresql[^\s\"]*://|redis://|rediss://")
                self.assertNotRegex(text, r"ghp_[a-zA-Z0-9]{30,}|AKIA[0-9A-Z]{16}")
        config = next(x for x in self.rendered["base"] if x["kind"] == "ConfigMap")["data"]
        self.assertFalse({"DATABASE_URL", "REDIS_URL", "POSTGRES_PASSWORD"} & config.keys())
        self.assertEqual(json.loads(config["CORS_ORIGINS"]), [])
        example = (BACKEND / "examples/backend-secrets.env.example").read_text(encoding="utf-8")
        self.assertIn("@postgres:5432/", example)
        self.assertIn("redis://redis:6379/", example)
        self.assertNotIn("localhost", example)

    def test_backend_processes_use_ghcr_and_shared_configuration(self):
        for target in ("base", "overlays/staging", "overlays/staging-rwx"):
            resources = self.rendered[target]
            for item in resources:
                spec = pod_spec(item)
                if not spec:
                    continue
                self.assertEqual(spec["serviceAccountName"], "backend-runtime")
                self.assertFalse(spec["automountServiceAccountToken"])
                for container in spec["containers"] + spec.get("initContainers", []):
                    self.assertRegex(container["image"], r"^ghcr.io/01phamtien/ai-recognition-(api|worker):")
                    self.assertNotIn(":latest", container["image"])
                for container in spec["containers"]:
                    refs = container["envFrom"]
                    self.assertIn({"configMapRef": {"name": "backend-config"}}, refs)
                    self.assertIn({"secretRef": {"name": "backend-secrets"}}, refs)

    def test_probes_separate_liveness_from_dependency_readiness(self):
        for target in ("base", "overlays/staging", "overlays/staging-rwx"):
            for item in self.rendered[target]:
                if item["kind"] != "Deployment":
                    continue
                container = pod_spec(item)["containers"][0]
                self.assertEqual(container["livenessProbe"]["httpGet"]["path"], "/health")
                self.assertEqual(container["readinessProbe"]["httpGet"]["path"], "/ready")
                self.assertEqual(container["startupProbe"]["httpGet"]["path"], "/health")
                # PostgreSQL connect_timeout=5 và Redis timeout=5 phải nằm trong probe budget.
                self.assertGreaterEqual(container["readinessProbe"]["timeoutSeconds"], 15)

    def test_all_containers_have_resource_budgets_and_security(self):
        for resources in self.rendered.values():
            for item in resources:
                spec = pod_spec(item)
                if not spec:
                    continue
                self.assertTrue(spec["securityContext"]["runAsNonRoot"])
                for container in spec["containers"] + spec.get("initContainers", []):
                    for budget in ("requests", "limits"):
                        self.assertIn("cpu", container["resources"][budget])
                        self.assertIn("memory", container["resources"][budget])
                    self.assertFalse(container["securityContext"]["allowPrivilegeEscalation"])
                    self.assertTrue(container["securityContext"]["readOnlyRootFilesystem"])
                    self.assertIn("ALL", container["securityContext"]["capabilities"]["drop"])

    def test_local_path_and_rwx_storage_are_not_confused(self):
        for target in ("overlays/staging", "overlays/staging-rwx"):
            resources = self.rendered[target]
            pvc = next(x for x in resources if x["kind"] == "PersistentVolumeClaim")
            is_local = target == "overlays/staging"
            self.assertEqual(pvc["spec"]["accessModes"], ["ReadWriteOnce"] if is_local else ["ReadWriteMany"])
            if is_local:
                self.assertEqual(pvc["spec"]["storageClassName"], "local-path")
            for item in resources:
                if item["kind"] != "Deployment":
                    continue
                spec = pod_spec(item)
                self.assertEqual(
                    next(v for v in spec["volumes"] if v["name"] == "uploads")["persistentVolumeClaim"]["claimName"],
                    pvc["metadata"]["name"],
                )
                if is_local:
                    self.assertEqual(spec["nodeSelector"], {"ai-recognition/upload-node": "true"})
                    self.assertEqual(item["spec"]["strategy"]["type"], "Recreate")
                else:
                    self.assertNotIn("nodeSelector", spec)

    def test_worker_model_is_initialised_and_main_container_is_read_only(self):
        worker = next(x for x in self.rendered["base"] if x["kind"] == "Deployment" and x["metadata"]["name"] == "worker")
        spec = pod_spec(worker)
        self.assertIn("scripts/download_model.py", spec["initContainers"][0]["command"])
        self.assertEqual(spec["initContainers"][0]["image"], spec["containers"][0]["image"])
        mount = next(m for m in spec["containers"][0]["volumeMounts"] if m["name"] == "model")
        self.assertTrue(mount["readOnly"])

    def test_service_selectors_and_prometheus_discovery_reach_each_backend(self):
        resources = self.rendered["overlays/staging"]
        deployments = [x for x in resources if x["kind"] == "Deployment"]
        services = [x for x in resources if x["kind"] == "Service"]
        for service in services:
            matches = [x for x in deployments if all(
                x["spec"]["template"]["metadata"]["labels"].get(k) == v
                for k, v in service["spec"]["selector"].items()
            )]
            self.assertEqual(len(matches), 1)
            template = matches[0]["spec"]["template"]
            container = template["spec"]["containers"][0]
            port = container["ports"][0]
            self.assertEqual(service["spec"]["ports"][0]["targetPort"], port["name"])
            annotations = template["metadata"]["annotations"]
            self.assertEqual(annotations["prometheus.io/scrape"], "true")
            self.assertEqual(annotations["prometheus.io/path"], "/metrics")
            self.assertEqual(int(annotations["prometheus.io/port"]), port["containerPort"])
        config = next(x for x in self.rendered["monitoring"] if x["kind"] == "ConfigMap")
        scrape = yaml.safe_load(config["data"]["prometheus.yml"])["scrape_configs"][0]
        self.assertEqual(scrape["kubernetes_sd_configs"][0]["role"], "pod")
        self.assertEqual(scrape["kubernetes_sd_configs"][0]["namespaces"]["names"], ["ai-recognition-staging"])
        # Không drop Pod unready: Worker vẫn cần được scrape khi đang xử lý inference lâu.
        self.assertNotIn("__meta_kubernetes_pod_ready", json.dumps(scrape))

    def test_schema_and_workloads_have_distinct_deployment_phases(self):
        for item in self.rendered["base"]:
            expected = "schema" if item["kind"] == "Job" else (
                "workload" if item["kind"] in ("Deployment", "Service") else "bootstrap"
            )
            self.assertEqual(item["metadata"]["labels"]["backend.ai-recognition/phase"], expected)


if __name__ == "__main__":
    if not shutil.which("kubectl"):
        raise SystemExit("Cần kubectl có Kustomize trong PATH.")
    unittest.main(verbosity=2)
