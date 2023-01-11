from dataclasses import dataclass
from pathlib import Path
from typing import Dict
from typing import List
from typing import Optional
from typing import Set
from typing import Tuple
from typing import TypeVar

from parsy import any_char
from parsy import Parser
from parsy import peek
from parsy import string
from parsy import success

from semdep.parsers.util import consume_line
from semdep.parsers.util import extract_npm_lockfile_hash
from semdep.parsers.util import json_doc
from semdep.parsers.util import mark_line
from semdep.parsers.util import not_any
from semdep.parsers.util import pair
from semdep.parsers.util import quoted
from semdep.parsers.util import safe_path_parse
from semdep.parsers.util import transitivity
from semdep.parsers.util import upto
from semgrep.semgrep_interfaces.semgrep_output_v1 import Ecosystem
from semgrep.semgrep_interfaces.semgrep_output_v1 import FoundDependency
from semgrep.semgrep_interfaces.semgrep_output_v1 import Npm
from semgrep.verbose_logging import getLogger


logger = getLogger(__name__)

A = TypeVar("A")


@dataclass
class YarnDep:
    line_number: int
    sources: List[Tuple[str, str]]
    data: Dict[str, str]


def source1(quoted: bool) -> "Parser[Tuple[str,str]]":
    return (
        string("@")
        .optional(default="")
        .bind(
            lambda at_prefix: upto(["@"], consume_other=True).bind(
                lambda package: not_any(
                    ['"', ","] + ([":"] if not quoted else [])
                ).bind(lambda version: success((at_prefix + package, version)))
            )
        )
    )


multi_source1 = (quoted(source1(True)) | source1(False)).sep_by(string(", "))

key_value1: "Parser[Optional[Tuple[str,str]]]" = (
    string(" ")
    .many()
    .bind(
        lambda spaces: consume_line
        if len(spaces) != 2
        else not_any([" ", ":"]).bind(
            lambda key: peek(any_char).bind(
                lambda next: consume_line
                if next == ":"
                else string(" ")
                >> not_any(["\n"]).bind(lambda value: success((key, value.strip('"'))))  # type: ignore
                # mypy seemingly cannot figure out that this function returns an optional
            )
        )
    )
)


yarn_dep1 = mark_line(
    pair(
        multi_source1 << string(":\n"),
        key_value1.sep_by(string("\n")).map(lambda xs: {x[0]: x[1] for x in xs if x}),
    )
)

YARN1_PREFIX = """\
# THIS IS AN AUTOGENERATED FILE. DO NOT EDIT THIS FILE DIRECTLY.
# yarn lockfile v1


"""

yarn1 = (
    string(YARN1_PREFIX) >> yarn_dep1.sep_by(string("\n\n")) << string("\n").optional()
)


source2 = (
    string("@")
    .optional(default="")
    .bind(
        lambda at_prefix: upto(["@"], consume_other=True).bind(
            lambda package: upto([":"], consume_other=True)
            >> upto(['"', ","]).bind(
                lambda version: success((at_prefix + package, version))
            )
        )
    )
)
multi_source2 = quoted(source2.sep_by(string(", ")))


key_value2: "Parser[Optional[Tuple[str,str]]]" = (
    string(" ")
    .many()
    .bind(
        lambda spaces: consume_line
        if len(spaces) != 2
        else not_any([":"]).bind(
            lambda key: string(":")
            >> peek(any_char).bind(
                lambda next: success(None)
                if next == "\n"
                else string(" ")
                >> not_any(["\n"]).bind(lambda value: success((key, value.strip('"'))))  # type: ignore
                # mypy seemingly cannot figure out that this function returns an optional
            )
        )
    )
)

yarn_dep2 = mark_line(
    pair(
        multi_source2 << string(":\n"),
        key_value2.sep_by(string("\n")).map(lambda xs: {x[0]: x[1] for x in xs if x}),
    )
)

YARN2_PREFIX = """\
# This file is generated by running "yarn install" inside your project.
# Manual changes might be lost - proceed with caution!

__metadata:
  version: 6
  cacheKey: 8

"""
yarn2 = (
    string(YARN2_PREFIX) >> yarn_dep2.sep_by(string("\n\n")) << string("\n").optional()
)


def get_manifest_deps(manifest_path: Optional[Path]) -> Optional[Set[Tuple[str, str]]]:
    if not manifest_path:
        return None
    json_opt = safe_path_parse(manifest_path, json_doc)
    if not json_opt:
        return None
    json = json_opt.as_dict()
    deps = json.get("dependencies")
    if not deps:
        return set()
    return {(x[0], x[1].as_str()) for x in deps.as_dict().items()}


def parse_yarn(
    lockfile_path: Path, manifest_path: Optional[Path]
) -> List[FoundDependency]:
    with open(lockfile_path) as f:
        lockfile_text = f.read()
    manifest_deps = get_manifest_deps(manifest_path)
    yarn_version = 1 if lockfile_text.startswith(YARN1_PREFIX) else 2
    parser = yarn1 if yarn_version == 1 else yarn2
    deps = safe_path_parse(lockfile_path, parser)
    if not deps:
        return []
    output = []
    for line_number, (sources, fields) in deps:
        if len(sources) < 1:
            continue
        if "version" not in fields:
            continue
        if yarn_version == 1:
            allowed_hashes = extract_npm_lockfile_hash(fields.get("integrity"))
        else:
            checksum = fields.get("checksum")
            allowed_hashes = {"sha512": [checksum]} if checksum else {}
        resolved_url = fields.get("resolved")
        output.append(
            FoundDependency(
                package=sources[0][0],
                version=fields["version"],
                ecosystem=Ecosystem(Npm()),
                allowed_hashes=allowed_hashes,
                resolved_url=resolved_url,
                transitivity=transitivity(manifest_deps, sources),
                line_number=line_number,
            )
        )
    return output
