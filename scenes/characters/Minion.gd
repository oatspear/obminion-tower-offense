extends KinematicBody2D

################################################################################
# Constants
################################################################################

const EPSILON = 1.0

enum FSM { IDLE, WALK, ATTACK, COOLDOWN, PURSUIT, DYING }


################################################################################
# Signals
################################################################################

signal spawn_projectile(projectile, source, target)
signal took_damage(amount)
signal died()


################################################################################
# Attributes
################################################################################

export (Global.Teams) var team: int = Global.Teams.NONE
export (int) var max_health: int = 20
export (int) var power: int = 2
export (float) var attack_speed: float = 1.0  # sec
export (Global.Projectiles) var projectile: int = Global.Projectiles.NONE
export (bool) var follows_lane: bool = true
export (int, 1, 5) var cost: int = Global.MIN_UNIT_COST

export (float) var move_speed = 30.0  # pixels / sec
var waypoint = null

var state: int = FSM.IDLE
var under_command: bool = false

var health: int = max_health
var attack_target: WeakRef = null

var timer: float = 0.0
var velocity: Vector2 = Vector2.ZERO

onready var sprite: AnimatedSprite = $Sprite
onready var range_area: Area2D = $Range
onready var health_bar = $HealthBar


################################################################################
# Interface
################################################################################

func cmd_move_to(point: Vector2) -> bool:
    if state == FSM.DYING:
        return false
    under_command = true
    waypoint = point
    _enter_walk()
    return true


func cmd_attack_target(target) -> bool:
    if state == FSM.DYING:
        return false
    under_command = true
    _enter_pursuit(target)
    return true


func set_waypoint(point: Vector2):
    waypoint = point


func is_alive() -> bool:
    return health > 0 and state != FSM.DYING


func is_idle() -> bool:
    return state == FSM.IDLE


func take_physical_damage(damage: int, _source: WeakRef):
    if state != FSM.DYING:
        health -= damage
        if health <= 0:
            _enter_dying()
        health_bar.set_value(health, max_health)
        emit_signal("took_damage", damage)


func do_attack():
    assert(attack_target != null)
    var target = attack_target.get_ref()
    if not target:
        return
    if projectile == Global.Projectiles.NONE:
        # print(name, " punches ", target.name)
        target.take_physical_damage(power, weakref(self))
    else:
        # print(name, " sends a projectile towards ", target.name)
        emit_signal("spawn_projectile", projectile, self, target)


################################################################################
# Event Handlers
################################################################################

func _on_Range_body_entered(body):
    if state != FSM.IDLE and state != FSM.WALK and state != FSM.PURSUIT:
        return
    if body.team == team or not body.is_alive():
        return
    if under_command:
        return
    if state == FSM.PURSUIT:
        assert(attack_target != null)
        if body != attack_target.get_ref():
            return
    _enter_attack(body)


func _on_Range_body_exited(body):
    if not attack_target:
        return
    if body == attack_target.get_ref():
        attack_target = null
        if state == FSM.ATTACK or state == FSM.PURSUIT or state == FSM.COOLDOWN:
            _enter_idle()


func _on_Sprite_animation_finished():
    match state:
        FSM.ATTACK:
            # punch/attack animation finished
            do_attack()
            _enter_cooldown()
        FSM.DYING:
            # death animation finished
            queue_free()


################################################################################
# Life Cycle
################################################################################

func _ready():
    collision_layer = Global.get_collision_layer(team)
    collision_mask = Global.get_collision_mask(team)
    range_area.collision_mask = Global.get_collision_mask_teams(team)
    health = max_health
    health_bar.set_value(health, max_health)
    sprite.animation = Global.ANIM_IDLE


func _process(delta: float):
    match state:
        FSM.IDLE:
            _process_idle(delta)
        FSM.ATTACK:
            _process_attack(delta)
        FSM.PURSUIT:
            _process_pursuit(delta)
        FSM.COOLDOWN:
            _process_cooldown(delta)
        _:
            pass


func _physics_process(delta: float):
    match state:
        FSM.WALK:
            _physics_process_walk(delta)
        FSM.PURSUIT:
            _physics_process_pursuit(delta)
        _:
            pass


func _enter_idle():
    # print(name, " --> IDLE")
    state = FSM.IDLE
    sprite.animation = Global.ANIM_IDLE
    attack_target = null
    under_command = false


func _enter_walk():
    # print(name, " --> WALK")
    state = FSM.WALK
    sprite.animation = Global.ANIM_WALK
    attack_target = null


func _enter_attack(target: Node2D):
    # print(name, " --> ATTACK")
    assert(target.team != team)
    state = FSM.ATTACK
    attack_target = weakref(target)
    # sprite.animation = Global.ANIM_CAST if is_caster else Global.ANIM_ATTACK
    sprite.animation = Global.ANIM_ATTACK
    sprite.flip_h = target.position.x < position.x
    timer = attack_speed


func _enter_cooldown():
    # print(name, " --> COOLDOWN")
    state = FSM.COOLDOWN
    sprite.animation = Global.ANIM_IDLE


func _enter_pursuit(target: Node2D):
    # print(name, "  --> PURSUIT")
    assert(target.team != team)
    if range_area.overlaps_body(target):
        _enter_attack(target)
    else:
        state = FSM.PURSUIT
        waypoint = target.position
        attack_target = weakref(target)
        sprite.animation = Global.ANIM_WALK
        sprite.flip_h = target.position.x < position.x


func _enter_dying():
    # print(name, " --> DYING")
    state = FSM.DYING
    health = 0
    power = 0
    move_speed = 0
    waypoint = null
    attack_target = null
    under_command = false
    velocity = Vector2.ZERO
    sprite.animation = Global.ANIM_DEATH
    emit_signal("died")


################################################################################
# Helper Functions
################################################################################

func _process_idle(delta):
#    timer -= delta
#    if timer > 0:
#        return
#    delta = -timer
#    timer = 0
    var target = _check_for_enemies()
    if target != null:
        _enter_attack(target)
        return _process_attack(delta)
    if waypoint != null:
        _enter_walk()


func _process_pursuit(_delta):
    assert(attack_target != null)
    var target = attack_target.get_ref()
    if not target:
        _enter_idle()


func _process_attack(delta: float):
    assert(timer > 0)
    timer -= delta
    if timer <= 0:
        timer = 0
        # ready to attack
        delta = -timer
        _enter_cooldown()
        _process_cooldown(delta)


func _process_cooldown(delta: float):
    timer -= delta
    if timer > 0:
        return
    delta = -timer
    timer = 0
    var target = attack_target.get_ref()
    if target and range_area.overlaps_body(target):
        _enter_attack(target)
        _process_attack(delta)
    else:
        _enter_idle()
        _process_idle(delta)


func _physics_process_walk(_delta):
    if waypoint == null:
        return
    velocity = _aim(waypoint)
    if velocity == Vector2.ZERO:
        waypoint = null
        _enter_idle()
        return
    sprite.flip_h = velocity.x < 0
    velocity *= move_speed
    velocity = move_and_slide(velocity)


func _physics_process_pursuit(delta):
    assert(attack_target != null)
    var target = attack_target.get_ref()
    if not target:
        _enter_idle()
        return
    waypoint = target.position
    _physics_process_walk(delta)
    if velocity.length_squared() < 1:
        _enter_idle()


func _aim(target: Vector2) -> Vector2:
    if position.distance_squared_to(target) < 4:
        return Vector2.ZERO
    return (target - position).normalized()

func _aim2(target: Vector2) -> Vector2:
    var dx = target.x - position.x
    var dy = target.y - position.y
    if dx < -EPSILON:
        if dy < -EPSILON:
            return Global.NORTHWEST
        if dy > EPSILON:
            return Global.SOUTHWEST
        return Global.WEST
    if dx > EPSILON:
        if dy < -EPSILON:
            return Global.NORTHEAST
        if dy > EPSILON:
            return Global.SOUTHEAST
        return Global.EAST
    if dy < -EPSILON:
        return Global.NORTH
    if dy > EPSILON:
        return Global.SOUTH
    return Vector2.ZERO


func _check_for_enemies():
    for target in range_area.get_overlapping_bodies():
        if target == self or target.team == team or not target.is_alive():
            continue
        return target
    return null
