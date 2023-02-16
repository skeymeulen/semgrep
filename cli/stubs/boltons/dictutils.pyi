from __future__ import annotations

from typing import Any
from typing import Iterator

class OneToOne:
    def __delitem__(self, key: int) -> None: ...
    def __init__(self, *a: Any, **kw: Any) -> None: ...
    def __setitem__(
        self, key: str | int, val: int | str | None
    ) -> None: ...
    def clear(self) -> None: ...
    def copy(self) -> OneToOne: ...
    def pop(self, key: int, default: Any = ...) -> int: ...
    def popitem(self) -> tuple[int, int]: ...
    def setdefault(self, key: int, default: None = ...) -> None: ...
    def update(self, dict_or_iterable: dict[int, int], **kw: Any) -> None: ...

class OrderedMultiDict:
    def __delitem__(self, k: str) -> None: ...
    def __eq__(  # type: ignore
        self,
        other: dict[str, int] | dict[str, str | dict[int, int]] | dict[int, int] | OrderedMultiDict,
    ) -> bool: ...
    def __getitem__(
        self, k: str | int
    ) -> int | str | OrderedMultiDict | None: ...
    def __init__(self, *args: Any, **kwargs: Any) -> None: ...
    def __iter__(self) -> Iterator[Any]: ...
    def __ne__(self, other: OrderedMultiDict) -> bool: ...  # type: ignore
    def __repr__(self) -> str: ...
    def __reversed__(self) -> Iterator[int]: ...
    def __setitem__(self, k: str, v: int | None) -> None: ...
    def _clear_ll(self) -> None: ...
    def _insert(
        self,
        k: str | int,
        v: int | OrderedMultiDict | str | None,
    ) -> None: ...
    def _remove(self, k: str) -> None: ...
    def _remove_all(self, k: str) -> None: ...
    def add(
        self,
        k: str | int,
        v: str | int | OrderedMultiDict | None,
    ) -> None: ...
    def clear(self) -> None: ...
    def copy(self) -> OrderedMultiDict: ...
    def getlist(self, k: str, default: Any = ...) -> list[int] | list[str]: ...
    def inverted(self) -> OrderedMultiDict: ...
    def items(
        self, multi: bool = ...
    ) -> list[tuple[str, int]] | list[tuple[str, str]] | list[tuple[int, str]]: ...
    def iteritems(
        self, multi: bool = ...
    ) -> Iterator[
        tuple[int, int] | tuple[str, None] | tuple[str, str] | tuple[str, int] | tuple[int, str]
    ]: ...
    def iterkeys(self, multi: bool = ...) -> Iterator[str | int]: ...
    def itervalues(self, multi: bool = ...) -> Iterator[str | int]: ...
    def keys(self, multi: bool = ...) -> list[int] | list[str]: ...
    def pop(self, k: str, default: Any = ...) -> str | int: ...
    def popall(
        self, k: str, default: Any = ...
    ) -> list[int] | list[str] | None: ...
    def poplast(self, k: Any = ..., default: Any = ...) -> str | int: ...
    def setdefault(self, k: str, default: Any = ...) -> None: ...
    def todict(self, multi: bool = ...) -> dict[str, int | str]: ...
    def update(
        self,
        E: list[tuple[int, int]] | list[tuple[str, OrderedMultiDict] | tuple[str, str]] | OrderedMultiDict,
        **F: Any,
    ) -> None: ...
    def update_extend(self, E: Any, **F: Any) -> None: ...
    def values(self, multi: bool = ...) -> list[int] | list[str]: ...
