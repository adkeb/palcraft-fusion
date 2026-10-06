// Extends the data-only mesh exporter with original banner/head/conduit factories.
import java.util.*;
import org.joml.*;
import com.mojang.math.Transformation;
import net.minecraft.core.Direction;
import net.minecraft.world.item.DyeColor;
import net.minecraft.client.model.geom.builders.LayerDefinition;
import net.minecraft.client.model.object.skull.*;
import net.minecraft.client.model.object.banner.*;
import net.minecraft.client.renderer.blockentity.*;

public final class DecorMeshOracle {
    static void export(String family,String variant,float input,net.minecraft.client.model.geom.ModelPart root,Transformation transform) {
        EntityMeshOracle.export(family,variant,input,root,transform);
    }
    static LayerDefinition head(String name) {
        return switch(name) {
            case "zombie","player" -> SkullModel.createHumanoidHeadLayer();
            case "piglin" -> LayerDefinition.create(PiglinHeadModel.createHeadModel(),64,64);
            case "dragon" -> DragonHeadModel.createHeadLayer();
            default -> SkullModel.createMobHeadLayer();
        };
    }
    static void banner(String variant,boolean standing,Transformation transform) {
        export("banner_body",variant,0,BannerModel.createBodyLayer(standing).bakeRoot(),transform);
        var root=BannerFlagModel.createFlagLayer(standing).bakeRoot();
        var flag=new BannerFlagModel(root);flag.setupAnim(0f);
        export("banner_flag",variant,0,root,transform);
    }
    static net.minecraft.client.model.geom.ModelPart posedHead(String type) {
        var root=head(type).bakeRoot();
        SkullModelBase model=type.equals("dragon")?new DragonHeadModel(root):type.equals("piglin")?new PiglinHeadModel(root):new SkullModel(root);
        model.setupAnim(new SkullModelBase.State());return root;
    }
    public static void main(String[] args) {
        Locale.setDefault(Locale.ROOT);
        for(int rotation=0;rotation<16;rotation++) {
            banner("free_"+rotation,true,BannerRenderer.TRANSFORMATIONS.freeTransformations(rotation));
            for(String type:List.of("skeleton","wither_skeleton","zombie","creeper","dragon","piglin","player"))
                export("skull_"+type,"free_"+rotation,0,posedHead(type),SkullBlockRenderer.TRANSFORMATIONS.freeTransformations(rotation));
        }
        for(Direction d:List.of(Direction.NORTH,Direction.SOUTH,Direction.EAST,Direction.WEST)) {
            banner("wall_"+d.getSerializedName(),false,BannerRenderer.TRANSFORMATIONS.wallTransformation(d));
            for(String type:List.of("skeleton","wither_skeleton","zombie","creeper","dragon","piglin","player"))
                export("skull_"+type,"wall_"+d.getSerializedName(),0,posedHead(type),SkullBlockRenderer.TRANSFORMATIONS.wallTransformation(d));
        }
        export("conduit","inactive",0,ConduitRenderer.createShellLayer().bakeRoot(),new Transformation(new Matrix4f().translation(.5f,.5f,.5f)));
        for(DyeColor color:DyeColor.values())
            System.out.printf("{\"type\":\"dye\",\"family\":\"dye\",\"name\":\"%s\",\"rgb\":%d}%n",color.getSerializedName(),color.getTextureDiffuseColor());
        System.out.printf("{\"type\":\"texture\",\"family\":\"skull_texture\",\"name\":\"player\",\"id\":\"%s\"}%n",net.minecraft.client.resources.DefaultPlayerSkin.getDefaultTexture());
    }
}
