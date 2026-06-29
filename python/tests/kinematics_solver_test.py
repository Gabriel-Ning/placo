import unittest
import placo
import numpy as np
import os

this_dir = os.path.dirname(os.path.realpath(__file__))


class TestKinematicsSolver(unittest.TestCase):
    def setUp(self):
        self.robot = placo.RobotWrapper(f"{this_dir}/quadruped/robot.urdf", placo.Flags.collision_as_visual)
        self.solver = self.robot.make_solver()

    def test_add_remove_task(self):
        self.assertEqual(self.solver.tasks_count(), 0, msg="There should be initially no task")

        regularization = self.solver.add_regularization_task(1e-6)
        self.assertEqual(self.solver.tasks_count(), 1, msg="There should be one task")

        self.solver.remove_task(regularization)
        self.assertEqual(self.solver.tasks_count(), 0, msg="There should be no more task")

        frame_task = self.solver.add_frame_task("trunk", np.eye(4))
        self.assertEqual(self.solver.tasks_count(), 2, msg="There should be two tasks")

        self.solver.remove_task(frame_task)
        self.assertEqual(self.solver.tasks_count(), 0, msg="There should be no more task")

    def test_acceleration_limits_from_rest(self):
        dt = 0.01
        a_max = 5.0
        joint = "leg1_a"

        self.robot.reset()
        self.robot.set_joint_velocity(joint, 0.0)
        self.robot.set_acceleration_limit(joint, a_max)

        self.solver.mask_fbase(True)
        self.solver.enable_joint_limits(False)
        self.solver.enable_velocity_limits(False)
        self.solver.enable_acceleration_limits(True)
        self.solver.dt = dt

        self.solver.add_joints_task({joint: 1.0})
        self.solver.add_regularization_task(1e-6)

        dq = self.solver.solve()
        v_idx = self.robot.get_joint_v_offset(joint)
        self.assertLessEqual(abs(dq[v_idx]), a_max * dt * dt + 1e-9)

    def test_acceleration_limits_steady_accel(self):
        dt = 0.01
        a_max = 5.0
        joint = "leg1_a"

        self.robot.reset()
        self.robot.set_acceleration_limit(joint, a_max)

        self.solver.mask_fbase(True)
        self.solver.enable_joint_limits(False)
        self.solver.enable_velocity_limits(False)
        self.solver.enable_acceleration_limits(True)
        self.solver.dt = dt

        joints_task = self.solver.add_joints_task({joint: 1.0})
        self.solver.add_regularization_task(1e-6)

        dq_prev = self.solver.solve(True)
        v_idx = self.robot.get_joint_v_offset(joint)
        joints_task.set_joint(joint, 1.0)
        dq = self.solver.solve()
        self.assertLessEqual(abs(dq[v_idx] - dq_prev[v_idx]), a_max * dt * dt + 1e-9)

    def test_acceleration_limits_braking_near_joint_limit(self):
        dt = 0.01
        a_max = 10.0
        joint = "leg1_a"
        lo, hi = self.robot.get_joint_limits(joint)
        target = hi - 0.05

        self.robot.reset()
        self.robot.set_joint(joint, hi - 0.1)
        self.robot.set_joint_velocity(joint, 0.0)
        self.robot.set_acceleration_limit(joint, a_max)

        self.solver.mask_fbase(True)
        self.solver.enable_joint_limits(True)
        self.solver.enable_velocity_limits(False)
        self.solver.enable_acceleration_limits(True)
        self.solver.dt = dt

        self.solver.add_joints_task({joint: target})
        self.solver.add_regularization_task(1e-6)

        dq = self.solver.solve(True)
        self.assertLessEqual(self.robot.get_joint(joint), hi + 1e-9)
        v_idx = self.robot.get_joint_v_offset(joint)
        self.assertLessEqual(abs(dq[v_idx]), a_max * dt * dt + 1e-9)

    def test_acceleration_limits_requires_dt(self):
        self.robot.set_acceleration_limits(1.0)
        self.solver.enable_acceleration_limits(True)
        self.solver.add_regularization_task(1e-6)

        with self.assertRaises(RuntimeError):
            self.solver.solve()


if __name__ == "__main__":
    unittest.main()
