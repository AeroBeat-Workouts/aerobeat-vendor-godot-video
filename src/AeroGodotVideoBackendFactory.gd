## Public vendor-specific factory entrypoint for the AeroBeat Godot video backend.
##
## Downstream consumers should treat this repo as a collision-safe backend/factory
## package layered underneath AeroVideoPlayerManager.
class_name AeroGodotVideoBackendFactory
extends RefCounted

const VERSION := "0.4.0"
const ManagerScript := preload("res://addons/aerobeat-tool-video-player/src/AeroVideoPlayerManager.gd")
const BackendScript := preload("AeroGodotVideoBackend.gd")
const SlotBankScript := preload("AeroGodotVideoSlotBank.gd")

func create_backend(player_factory: Callable = Callable()) -> RefCounted:
	var backend := BackendScript.new()
	if player_factory.is_valid():
		backend.set_player_factory(player_factory)
	return backend

func create_manager(player_factory: Callable = Callable()) -> Node:
	var manager = ManagerScript.new()
	manager.set_backend_factory(func() -> AeroVideoPlayerBackend:
		return create_backend(player_factory)
	)
	manager.set_backend(create_backend(player_factory))
	return manager

func create_slot_bank(player_factory: Callable = Callable()) -> AeroGodotVideoSlotBank:
	return SlotBankScript.new(self, player_factory)

func build_manager(surface: Node = null, source: Dictionary = {}, player_factory: Callable = Callable()) -> Node:
	var manager = create_manager(player_factory)
	if surface != null:
		manager.attach_surface(surface)
	if not source.is_empty():
		manager.load(source)
	return manager

func build_slot_bank(slot_sources: Dictionary = {}, slot_surfaces: Dictionary = {}, player_factory: Callable = Callable()) -> AeroGodotVideoSlotBank:
	var slot_bank := create_slot_bank(player_factory)
	for slot_name_variant in slot_surfaces.keys():
		var slot_name := str(slot_name_variant)
		var surface: Node = slot_surfaces.get(slot_name_variant, null)
		if surface != null:
			slot_bank.attach_slot_surface(slot_name, surface)
	for slot_name_variant in slot_sources.keys():
		var slot_name := str(slot_name_variant)
		var source: Variant = slot_sources.get(slot_name_variant, {})
		if source is Dictionary:
			slot_bank.load_slot(slot_name, Dictionary(source).duplicate(true))
	return slot_bank
