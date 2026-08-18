from __future__ import annotations

import asyncio
from types import SimpleNamespace
from typing import Any, cast

import pytest

import agent


class FakePublication:
    def __init__(self, kind: Any) -> None:
        self.kind = kind
        self.subscribed = False

    def set_subscribed(self, subscribed: bool) -> None:
        self.subscribed = subscribed


class FakeParticipant:
    def __init__(self, identity: str, *publications: FakePublication) -> None:
        self.identity = identity
        self.track_publications = {
            f"track-{index}": publication for index, publication in enumerate(publications)
        }


class FakeLocalParticipant:
    def __init__(self) -> None:
        self.subscription_permissions: dict[str, Any] | None = None

    def set_track_subscription_permissions(self, **kwargs: Any) -> None:
        self.subscription_permissions = kwargs


class FakeRoom:
    def __init__(self, *participants: FakeParticipant) -> None:
        self.name = "audit-room"
        self.remote_participants = {
            participant.identity: participant for participant in participants
        }
        self.local_participant = FakeLocalParticipant()
        self._callbacks: dict[str, object] = {}

    def on(self, event: str, callback: object) -> None:
        self._callbacks[event] = callback

    def off(self, event: str, callback: object) -> None:
        if self._callbacks.get(event) is callback:
            self._callbacks.pop(event, None)

    def emit_participant(self, participant: FakeParticipant) -> None:
        callback = self._callbacks.get("participant_connected")
        assert callable(callback)
        callback(participant)

    def emit_track_published(
        self,
        publication: FakePublication,
        participant: FakeParticipant,
    ) -> None:
        callback = self._callbacks.get("track_published")
        assert callable(callback)
        callback(publication, participant)


class FakeRoomAPI:
    def __init__(self, *, fail_removal: bool = False) -> None:
        self.fail_removal = fail_removal
        self.removed: list[str] = []

    async def remove_participant(self, request: Any) -> None:
        if self.fail_removal:
            raise RuntimeError("simulated removal failure")
        self.removed.append(request.identity)


class FakeContext:
    def __init__(self, room: FakeRoom, *, fail_removal: bool = False) -> None:
        self.room = room
        self.api = SimpleNamespace(room=FakeRoomAPI(fail_removal=fail_removal))
        self.connected = False
        self.connect_kwargs: dict[str, Any] = {}
        self.deleted = False

    async def connect(self, **kwargs: Any) -> None:
        self.connected = True
        self.connect_kwargs = kwargs

    async def delete_room(self) -> None:
        self.deleted = True


def as_job_context(ctx: FakeContext) -> Any:
    """Explicitly mark the test double as intentional at the typed SDK boundary."""
    return cast(Any, ctx)


@pytest.mark.asyncio
async def test_guard_selects_allowlisted_participant_and_evicts_unknown(monkeypatch):
    monkeypatch.setenv("VELTS_BAD_ALLOWED_IDENTITIES", "velts")
    intruder = FakeParticipant("intruder")
    velts = FakeParticipant("velts")
    ctx = FakeContext(FakeRoom(intruder, velts))

    participant, guard = await agent.wait_for_private_participant(as_job_context(ctx))

    assert participant is velts
    assert guard is not None
    assert ctx.api.room.removed == ["intruder"]
    assert ctx.connect_kwargs["auto_subscribe"] == agent.AutoSubscribe.SUBSCRIBE_NONE
    assert not ctx.deleted


@pytest.mark.asyncio
async def test_guard_fails_closed_when_eviction_fails(monkeypatch):
    monkeypatch.setenv("VELTS_BAD_ALLOWED_IDENTITIES", "velts")
    intruder = FakeParticipant("intruder")
    velts = FakeParticipant("velts")
    ctx = FakeContext(FakeRoom(intruder, velts), fail_removal=True)

    participant, guard = await agent.wait_for_private_participant(as_job_context(ctx))

    assert participant is None
    assert guard is None
    assert ctx.deleted


@pytest.mark.asyncio
async def test_late_second_allowlisted_contact_is_evicted(monkeypatch):
    monkeypatch.setenv("VELTS_BAD_ALLOWED_IDENTITIES", "velts,alice")
    velts = FakeParticipant("velts")
    ctx = FakeContext(FakeRoom(velts))

    participant, guard = await agent.wait_for_private_participant(as_job_context(ctx))
    assert participant is velts
    assert guard is not None

    ctx.room.emit_participant(FakeParticipant("alice"))
    for _ in range(5):
        await asyncio.sleep(0)
        if ctx.api.room.removed:
            break

    assert ctx.api.room.removed == ["alice"]
    assert not ctx.deleted


def test_private_media_only_subscribes_linked_audio_and_restricts_output(monkeypatch):
    # The production mapping contains rtc.RemoteTrackPublication instances. Patch
    # the SDK class symbol so the lightweight test double models that invariant.
    monkeypatch.setattr(agent.rtc, "RemoteTrackPublication", FakePublication)

    linked_audio = FakePublication(agent.rtc.TrackKind.KIND_AUDIO)
    linked_video = FakePublication(agent.rtc.TrackKind.KIND_VIDEO)
    intruder_audio = FakePublication(agent.rtc.TrackKind.KIND_AUDIO)
    velts = FakeParticipant("velts", linked_audio, linked_video)
    intruder = FakeParticipant("intruder", intruder_audio)
    ctx = FakeContext(FakeRoom(velts, intruder))

    callback = agent.configure_private_media(as_job_context(ctx), velts)

    assert callback is not None
    assert linked_audio.subscribed
    assert not linked_video.subscribed
    assert not intruder_audio.subscribed

    permissions = ctx.room.local_participant.subscription_permissions
    assert permissions is not None
    assert permissions["allow_all_participants"] is False
    participant_permissions = permissions["participant_permissions"]
    assert len(participant_permissions) == 1
    assert participant_permissions[0].participant_identity == "velts"
    assert participant_permissions[0].allow_all is True

    late_linked_audio = FakePublication(agent.rtc.TrackKind.KIND_AUDIO)
    late_intruder_audio = FakePublication(agent.rtc.TrackKind.KIND_AUDIO)
    ctx.room.emit_track_published(late_linked_audio, velts)
    ctx.room.emit_track_published(late_intruder_audio, intruder)

    assert late_linked_audio.subscribed
    assert not late_intruder_audio.subscribed
