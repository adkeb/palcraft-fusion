// Extract exact closed chest cuboids/UVs from the installed MC model factory.
// This is data extraction only: no graphical client or world is started.
import java.util.Locale;
import org.joml.Vector3f;
import com.mojang.blaze3d.vertex.PoseStack;
import net.minecraft.client.model.object.chest.ChestModel;
import net.minecraft.client.model.geom.ModelPart;
import net.minecraft.client.model.geom.builders.LayerDefinition;

public final class ChestMeshOracle {
    static void export(String variant, LayerDefinition layer) {
        var root = layer.bakeRoot();
        root.visit(new PoseStack(), (pose, path, index, cube) -> {
            for (var face : cube.polygons) {
                var normal = new Vector3f(face.normal());
                pose.normal().transform(normal);
                normal.normalize();
                System.out.printf("{\"variant\":\"%s\",\"part\":\"%s\",\"normal\":[%.9f,%.9f,%.9f],\"vertices\":[",variant,path,normal.x,normal.y,normal.z);
                int vertexIndex=0;
                for (var v:face.vertices()) {
                    var p = new Vector3f(v.worldX(),v.worldY(),v.worldZ());
                    pose.pose().transformPosition(p);
                    if (vertexIndex++>0)System.out.print(",");
                    System.out.printf("[%.9f,%.9f,%.9f,%.9f,%.9f]",p.x,p.y,p.z,v.u(),v.v());
                }
                System.out.println("]}");
            }
        });
    }
    public static void main(String[] args) {
        Locale.setDefault(Locale.ROOT);
        export("single",ChestModel.createSingleBodyLayer());
        export("left",ChestModel.createDoubleBodyLeftLayer());
        export("right",ChestModel.createDoubleBodyRightLayer());
    }
}
