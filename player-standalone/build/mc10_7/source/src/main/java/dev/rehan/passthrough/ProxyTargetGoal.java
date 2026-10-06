package dev.rehan.passthrough;

import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.ai.goal.target.NearestAttackableTargetGoal;
import net.minecraft.world.entity.npc.villager.Villager;

/** Pal server actors participate in normal MC targeting; only the bridge's own invisibility is ignored. */
final class ProxyTargetGoal extends NearestAttackableTargetGoal<Villager> {
	ProxyTargetGoal(final Mob mob) {
		super(mob, Villager.class, 10, false, false, (target, level) -> MobWar.isProxy(target));
		this.targetConditions.ignoreInvisibilityTesting();
	}
}
