# type: ignore
# Used for pre-commit since it expects a setup.py in repo root
# for actual setup.py see cli/setup.py
from setuptools import setup(
    long_description_content_type="text/markdown",
    )

setup(
    name="semgrep_pre_commit_package",
    version="1.22.0",
    install_requires=["semgrep==1.22.0"],
    packages=[],
)
