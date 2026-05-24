## Public vendor-specific factory entrypoint for the AeroBeat Godot video backend.
##
## Downstream consumers should treat this repo as a collision-safe backend/factory
## package layered underneath AeroVideoPlayerManager.
class_name AeroGodotVideoBackendFactory
extends RefCounted

const VERSION := "0.2.0"
const ManagerScript := preload("res://addons/aerobeat-tool-video-player/src/AeroVideoPlayerManager.gd")
const BackendScript := preload("AeroGodotVideoBackend.gd")

func create_backend(player_factory: Callable = Callable()) -> AeroVideoVendorBackend:
	var backend := BackendScript.new()
	if player_factory.is_valid():
		backend.set_player_factory(player_factory)
	return backend

func create_manager(player_factory: Callable = Callable()) -> Node:
	var manager = ManagerScript.new()
	manager.set_backend(create_backend(player_factory))
	return manager

func build_manager(surface: Node = null, source: Dictionary = {}, player_factory: Callable = Callable()) -> Node:
	var manager = create_manager(player_factory)
	if surface != null:
		manager.attach_surface(surface)
	if not source.is_empty():
		manager.load(source)
	return manager
