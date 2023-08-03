from dataclasses import dataclass


# delta is designed for integer variables/parameters.
@dataclass
class Variable:
    name: str
    default: float
    minval: float
    maxval: float
    delta: float
    apply_factor: float


VARIABLES = [
    Variable("LMRWeight", 580.0, 100.0, 900.0, 260.0, 0.45),
    Variable("LMRBias", 980.0, 100.0, 1500.0, 500.0, 0.4),
]


WORKING_DIRECTORY = "./engine"
ENGINE_COMMAND = "./Avalanche"
CUTECHESS_COMMAND = """./cutechess-cli -tournament gauntlet \
-concurrency 7 -recover -pgnout games.pgn \
-draw movenumber=40 movecount=4 score=2 -resign movecount=4 score=300 \
-each proto=uci -openings file=UHO.pgn format=pgn -repeat -games 50""".split()
TIME_CONTROL = "15.0+0.12"
HASH = 64

NUM_ITERATIONS = 10
