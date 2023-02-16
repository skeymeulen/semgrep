from __future__ import annotations

from itertools import chain
from typing import Any
from typing import Callable
from typing import TypeVar

C = TypeVar("C")

def _indent(
    text: str, margin: str, newline: str = ..., key: type[bool] = ...
) -> str: ...
def copy_function(orig: Callable, copy_dict: bool = ...) -> Callable: ...
def mro_items(type_obj: type[C]) -> chain: ...
def wraps(
    func: classmethod | Callable,
    injected: str | list[str] | None = ...,
    **kw: Any,
) -> Callable: ...

class CachedInstancePartial:
    def __get__(self, obj: C, obj_type: type[C]) -> Callable: ...

class FunctionBuilder:
    def __init__(self, name: str, **kw: Any) -> None: ...
    @classmethod
    def _argspec_to_dict(cls, f: Callable) -> dict[str, Any]: ...
    def _compile(self, src: str, execdict: dict[Any, Any]) -> dict[Any, Any]: ...
    @classmethod
    def from_func(cls, func: Callable) -> FunctionBuilder: ...
    def get_defaults_dict(self) -> dict[str, str]: ...
    def get_func(
        self,
        execdict: dict[str, Callable] | None = ...,
        add_source: bool = ...,
        with_dict: bool = ...,
    ) -> Callable: ...
    def get_invocation_str(self) -> str: ...
    def get_sig_str(self) -> str: ...
    def remove_arg(self, arg_name: str) -> None: ...

class InstancePartial:
    def __get__(self, obj: C, obj_type: type[C]) -> Callable: ...
