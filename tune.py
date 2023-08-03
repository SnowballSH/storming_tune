import pathlib
import numpy as np
import math
import json
import subprocess
import re
from dataclasses import dataclass
from typing import List

import config


RNG = np.random.default_rng()


@dataclass
class TuningVariable:
    name: str
    value: float

    def from_variable(var: config.Variable):
        return TuningVariable(var.name, var.default)


def generate_json(a_variables, b_variables):
    data = [
        {
            "command": config.ENGINE_COMMAND,
            "name": "A",
            "options": [{"name": "Hash", "value": config.HASH}],
            "protocol": "uci",
            "workingDirectory": ".",
        },
        {
            "command": config.ENGINE_COMMAND,
            "name": "B",
            "options": [{"name": "Hash", "value": config.HASH}],
            "protocol": "uci",
            "workingDirectory": ".",
        },
    ]

    for var in a_variables:
        data[0]["options"].append({"name": var.name, "value": int(round(var.value))})

    for var in b_variables:
        data[1]["options"].append({"name": var.name, "value": int(round(var.value))})

    return json.dumps(data, indent=4)


def gaussian_random(a: float, b: float, x: float):
    # Calculate the standard deviation.
    std_dev = abs(b - a) / 6

    steps = 0

    while True:
        # Generate a Gaussian-distributed random number.
        num = RNG.normal(x, std_dev)
        steps += 1

        # If the number falls in the range [a, b], return it.
        if a <= num <= b:
            return num

        if steps == 2000:
            print(
                f"Warning: The current value ({x}) is too close to the bounds of the range ([{a}, {b}]). Please consider extending the range."
            )


def random_delta(delta: float):
    return gaussian_random(-delta, delta, 0)


def play_match(a_variables, b_variables):
    json_string = generate_json(a_variables, b_variables)

    with open(pathlib.Path(config.WORKING_DIRECTORY, "engines.json"), "w") as f:
        f.write(json_string)

    cmd = config.CUTECHESS_COMMAND
    cmd.extend(f"-engine conf=A tc={config.TIME_CONTROL}".split())
    cmd.extend(f"-engine conf=B tc={config.TIME_CONTROL}".split())

    process = subprocess.Popen(
        cmd, cwd=config.WORKING_DIRECTORY, stdout=subprocess.PIPE
    )
    process.wait()

    for line in process.stdout.read().decode().split("\n"):
        if "Score of A vs B" in line:
            return float(re.search(r"\[([0-9\.]+)\]", line).group(1))


def main():
    variables: List[TuningVariable] = [
        TuningVariable.from_variable(var) for var in config.VARIABLES
    ]
    for iteration in range(config.NUM_ITERATIONS):
        print(f"Iteration {iteration + 1}/{config.NUM_ITERATIONS}")
        for variable in variables:
            print(f"{variable.name}: {variable.value}")

        print("Choosing delta:")

        variables_a = []
        variables_b = []
        deltas = []
        for i, variable in enumerate(variables):
            delta = random_delta(config.VARIABLES[i].delta)
            deltas.append(delta)
            print(f"Delta for {variable.name}: {delta}")
            next_value_a, next_value_b = np.clip(
                [variable.value + delta, variable.value - delta],
                config.VARIABLES[i].minval,
                config.VARIABLES[i].maxval,
            ).tolist()
            variables_a.append(TuningVariable(variable.name, next_value_a))
            variables_b.append(TuningVariable(variable.name, next_value_b))

        print(f"Starting match between A and B:\n{variables_a}\n{variables_b}")
        result = play_match(variables_a, variables_b)
        print(f"Result: A won {result * 100} %")

        if result > 0.5:
            dt = 1
        elif result < 0.5:
            dt = -1
        else:
            dt = RNG.choice([-1, 1])
            print("Draw, randomly choosing dt")
        print(f"dt = {dt}")

        for i, variable in enumerate(variables):
            variable.value += dt * config.VARIABLES[i].apply_factor * deltas[i]
            variable.value = np.clip(
                variable.value, config.VARIABLES[i].minval, config.VARIABLES[i].maxval
            )

    print("Final values:")
    for variable in variables:
        print(f"{variable.name}: {variable.value}")


if __name__ == "__main__":
    main()
