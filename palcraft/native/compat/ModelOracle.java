// Runs data-only checks against the user's installed Minecraft version.
import java.util.Locale;
import org.joml.Vector3f;
import net.minecraft.core.Direction;
import net.minecraft.util.Mth;
import net.minecraft.util.RandomSource;
import com.mojang.math.Quadrant;
import net.minecraft.client.renderer.block.dispatch.Variant;

public final class ModelOracle {
    public static void main(String[] args) {
        Locale.setDefault(Locale.ROOT);
        for (int x = 0; x < 4; x++) for (int y = 0; y < 4; y++) for (int z = 0; z < 4; z++) {
            var state = new Variant.SimpleModelState(Quadrant.values()[x], Quadrant.values()[y], Quadrant.values()[z], true).asModelState();
            for (Direction d : Direction.values()) {
                Vector3f v = new Vector3f(.13f - .5f, .71f - .5f, 0);
                state.faceTransformation(d).transformPosition(v);
                Vector3f p = new Vector3f(.17f - .5f, .31f - .5f, .73f - .5f);
                state.transformation().getMatrix().transformPosition(p);
                System.out.printf("{\"type\":\"uv\",\"x\":%d,\"y\":%d,\"z\":%d,\"face\":\"%s\",\"uv\":[%.9f,%.9f],\"point\":[%.9f,%.9f,%.9f]}%n",x*90,y*90,z*90,d.getSerializedName(),v.x+.5,v.y+.5,p.x+.5,p.y+.5,p.z+.5);
            }
        }
        int[][] points = {{0,64,0},{7,63,-15},{-12345,82,28761},{-30000000,64,30000000},{1,0,1},{-1,-64,-1}};
        for (int[] p:points) {
            long seed = Mth.getSeed(p[0],p[1],p[2]);
            var r = RandomSource.create(seed);
            int a=r.nextInt(2),b=r.nextInt(3),c=r.nextInt(17),d=r.nextInt(1000000007);
            var multi = RandomSource.create(seed);
            long multipartSeed = multi.nextLong();
            multi.setSeed(multipartSeed);
            int choice = multi.nextInt(19);
            System.out.printf("{\"type\":\"random\",\"position\":[%d,%d,%d],\"seed\":\"%d\",\"samples\":[%d,%d,%d,%d],\"multipart_seed\":\"%d\",\"multipart_choice\":%d}%n",p[0],p[1],p[2],seed,a,b,c,d,multipartSeed,choice);
        }
    }
}
