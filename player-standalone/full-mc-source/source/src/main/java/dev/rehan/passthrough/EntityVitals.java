package dev.rehan.passthrough;

/** Pure ratios: form changes never write Pal HP, shield, hunger, inventory or revive state. */
public final class EntityVitals {
    private EntityVitals() {}
    public static float health(double hp,double maxHp,boolean alive,boolean dying){
        require(hp,maxHp);
        return alive&&!dying?(float)Math.clamp(hp/maxHp*20,0,20):0;
    }
    public static int food(double stomach,double maxStomach){
        require(stomach,maxStomach);
        return (int)Math.clamp(Math.ceil(stomach/maxStomach*20),0,20);
    }
    private static void require(double current,double maximum){
        if(!Double.isFinite(current)||!Double.isFinite(maximum)||current<0||maximum<=0)
            throw new IllegalArgumentException("Authoritative vital range required");
    }
}
