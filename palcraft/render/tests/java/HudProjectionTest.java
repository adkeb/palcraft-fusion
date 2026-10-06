import dev.rehan.passthrough.client.GuideProjection;
import org.joml.Quaterniond;
import org.joml.Vector3d;
import java.util.Random;

public final class HudProjectionTest {
    private static int checks;
    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
        checks++;
    }
    private static void near(double actual, double expected, String message) {
        check(Math.abs(actual - expected) < 1e-7, message + ": " + actual + " != " + expected);
    }
    public static void main(String[] args) {
        var flat = new GuideProjection.Camera(0,0,0,0,0,0,90);
        double[] center = GuideProjection.project(flat,1920,1080,0,0,2);
        near(center[0],960,"center x");near(center[1],540,"center y");
        double[] right = GuideProjection.project(flat,1920,1080,-1,0,2);
        near(right[0],1230,"MC yaw0 right is -X");near(right[1],540,"right y");
        var roll = new GuideProjection.Camera(0,0,0,0,0,90,90);
        double[] rolled = GuideProjection.project(roll,1920,1080,0,1,2);
        near(rolled[0],1230,"roll rotates +Y to screen right");near(rolled[1],540,"roll y");
        check(GuideProjection.project(flat,100,100,0,0,-1)==null,"behind camera");
        check(GuideProjection.segment(flat,100,100,0,0,-1,0,1,-2)==null,"both endpoints behind");
        double[] clipped=GuideProjection.segment(flat,100,100,100,0,2,-100,0,2);
        near(clipped[0],0,"viewport left");near(clipped[2],99,"viewport right");
        check(GuideProjection.segment(flat,100,100,100,0,-1,0,0,1)!=null,"near-plane crossing");
        check(GuideProjection.project(new GuideProjection.Camera(0,0,0,0,0,0,Double.NaN),100,100,0,0,1)==null,"invalid FOV");
        check(GuideProjection.project(flat,0,100,0,0,1)==null,"zero viewport");
        // The overlay is resized to Pal's client rectangle. Projection must
        // preserve the native camera after that non-uniform resize.
        for(double hostAspect:new double[]{4.0/3,16.0/9,21.0/9,1440.0/872}) {
            var host=new GuideProjection.Camera(0,0,0,0,0,0,70,hostAspect);
            double[] gui=GuideProjection.project(host,1920,1080,-1,.2,3);
            double hostHeight=872,hostWidth=hostHeight*hostAspect;
            double hostScale=hostHeight/(2*Math.tan(Math.toRadians(70)/2));
            near(gui[0]*hostWidth/1920,hostWidth/2+hostScale/3,"resized Pal x");
            near(gui[1]*hostHeight/1080,hostHeight/2-.2*hostScale/3,"resized Pal y");
        }
        Random random=new Random(7193);
        int[][] viewports={{1920,1080},{1280,960},{2520,1080},{1440,872}};
        for(int i=0;i<10000;i++) {
            double yaw=random.nextDouble()*360-180,pitch=random.nextDouble()*160-80,rollAngle=random.nextDouble()*120-60;
            double fov=random.nextDouble()*110+30,x=random.nextDouble()*2000-1000,y=random.nextDouble()*200-100,z=random.nextDouble()*2000-1000;
            var camera=new GuideProjection.Camera(x,y,z,yaw,pitch,rollAngle,fov);
            Quaterniond rotation=new Quaterniond().rotationYXZ(Math.PI-Math.toRadians(yaw),-Math.toRadians(pitch),Math.toRadians(rollAngle));
            double f=random.nextDouble()*30+.2;
            Vector3d inCamera=new Vector3d((random.nextDouble()-.5)*f,(random.nextDouble()-.5)*f,-f);
            Vector3d inWorld=rotation.transform(new Vector3d(inCamera)).add(x,y,z);
            int[] viewport=viewports[i%viewports.length];
            double[] actual=GuideProjection.project(camera,viewport[0],viewport[1],inWorld.x,inWorld.y,inWorld.z);
            double scale=viewport[1]/(2*Math.tan(Math.toRadians(fov)/2));
            near(actual[0],viewport[0]*.5+inCamera.x/f*scale,"quaternion x");
            near(actual[1],viewport[1]*.5-inCamera.y/f*scale,"quaternion y");
            double[] line=GuideProjection.segment(camera,viewport[0],viewport[1],inWorld.x,inWorld.y,inWorld.z,x,y,z);
            if(line!=null)for(int n=0;n<4;n++)check(Double.isFinite(line[n])&&line[n]>=-1e-7&&line[n]<=(n%2==0?viewport[0]-1:viewport[1]-1)+1e-7,"finite clipped segment");
        }
        System.out.println("{\"status\":\"passed\",\"projection_checks\":"+checks+",\"random_cameras\":10000,\"aspects\":[\"16:9\",\"4:3\",\"21:9\",\"Mac-content\"],\"oracle\":\"JOML Quaterniond rotationYXZ used by CameraMixin\"}");
    }
}
