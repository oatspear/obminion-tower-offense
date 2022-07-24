extends Sprite

################################################################################
# Constants
################################################################################

enum FSM { TRAVEL, IMPACT, DECAY }


################################################################################
# Variables
################################################################################

export (int) var power: int = 1
export (float) var speed: float = 120  # pixels / sec
export (float) var decay: float = 0.125  # secs

var target: Node2D
var travel_distance: float = 0.0

onready var state = FSM.TRAVEL


################################################################################
# Interface
################################################################################

func do_effect():
    if target != null:
        target.take_physical_damage(power)


################################################################################
# Life Cycle
################################################################################

func _ready():
    # requires: set initial position
    # requires: set target
    # requires: set power
    travel_distance = position.distance_to(target.position)
    var dx = target.position.x - position.x
    var dy = target.position.y - position.y
    if abs(dx) >= abs(dy):
        # more horizontal than vertical
        frame = 1
        flip_h = dx < 0
        flip_v = dy > 0
    else:
        # more vertical than horizontal
        flip_h = dx > 0
        flip_v = dy > 0


func _physics_process(delta):
    if state != FSM.TRAVEL:
        return
    if position.distance_to(target.position) < 1:
        state = FSM.IMPACT
    else:
        var vel: Vector2 = target.position - position
        vel = vel.normalized() * speed * delta
        position += vel
        travel_distance -= vel.length()
        if travel_distance <= 0 and state == FSM.TRAVEL:
            state = FSM.IMPACT
            target = null


func _process(delta):
    if state == FSM.IMPACT:
        state = FSM.DECAY
        do_effect()
    if state == FSM.DECAY:
        decay -= delta
        if decay <= 0:
            queue_free()
