import dev.rehan.passthrough.client.signtext.SignGlyphRaster;
import java.util.List;

/** Small shader/coverage regression, no game classes or GPU startup. */
public final class SignGlyphRasterTest {
    static void check(boolean condition, String reason) { if (!condition) throw new AssertionError(reason); }
    static SignGlyphRaster.Vertex v(double x, double y, double u, double w, int color) {
        return new SignGlyphRaster.Vertex(x,y,u,w,color);
    }
    static SignGlyphRaster.Quad quad(double x, double y, double width, double height, int color) {
        return new SignGlyphRaster.Quad(0,v(x,y,0,0,color),v(x,y+height,0,1,color),
            v(x+width,y+height,1,1,color),v(x+width,y,1,0,color));
    }
    public static void main(String[] args) {
        var bounds = new SignGlyphRaster.Bounds(0,0,2,2);
        var white = new SignGlyphRaster.Atlas(1,1,true,new byte[]{(byte)255});
        var image = SignGlyphRaster.render(bounds,1,List.of(white),List.of(quad(0,0,2,2,0x80ff0000)),new float[]{1,1,1});
        for (int y=0;y<2;y++) for (int x=0;x<2;x++)
            check(image.getRGB(x,y)==0x80ff0000,"quad diagonal blended twice");
        var gray = new SignGlyphRaster.Atlas(1,1,true,new byte[]{(byte)128});
        image = SignGlyphRaster.render(bounds,1,List.of(gray),List.of(quad(0,0,2,2,0xff8040ff)),new float[]{1,1,1});
        check(image.getRGB(0,0)==0x80402080,"grayscale must sample .rrrr including alpha");
        var rgba = new SignGlyphRaster.Atlas(2,2,false,new byte[]{
            (byte)255,0,0,(byte)255, 0,(byte)255,0,(byte)255,
            0,0,(byte)255,(byte)255, 0,0,0,0});
        image = SignGlyphRaster.render(bounds,1,List.of(rgba),List.of(quad(0,0,2,2,0xffffffff)),new float[]{1,1,1});
        check(image.getRGB(0,0)==0xffff0000 && image.getRGB(1,0)==0xff00ff00
            && image.getRGB(0,1)==0xff0000ff && image.getRGB(1,1)==0,"nearest atlas UV/row orientation");
        var below = new SignGlyphRaster.Atlas(1,1,true,new byte[]{25});
        var above = new SignGlyphRaster.Atlas(1,1,true,new byte[]{26});
        check(SignGlyphRaster.render(bounds,1,List.of(below),List.of(quad(0,0,2,2,-1)),new float[]{1,1,1}).getRGB(0,0)==0,"vanilla .1 discard below");
        check(SignGlyphRaster.render(bounds,1,List.of(above),List.of(quad(0,0,2,2,-1)),new float[]{1,1,1}).getRGB(0,0)!=0,"vanilla .1 discard above");
        var outline = new java.util.ArrayList<SignGlyphRaster.Quad>();
        for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++)if(x!=0||y!=0)outline.add(quad(x,y,1,1,0xff000000));
        outline.add(quad(0,0,1,1,0xffffffff));
        image=SignGlyphRaster.render(new SignGlyphRaster.Bounds(-1,-1,2,2),1,List.of(white),outline,new float[]{1,1,1});
        check(image.getRGB(1,1)==0xffffffff && image.getRGB(0,0)==0xff000000 && image.getRGB(2,2)==0xff000000,"outline must remain behind main glyph");
        byte[] light=new byte[16*16*4];
        light[(15*16+3)*4]=64;light[(15*16+3)*4+1]=(byte)128;light[(15*16+3)*4+2]=(byte)255;
        var sampled=SignGlyphRaster.light(new SignGlyphRaster.Atlas(16,16,false,light),240<<16|48);
        check(Math.abs(sampled[0]-64/255f)<1e-6 && Math.abs(sampled[1]-128/255f)<1e-6 && sampled[2]==1,"packed vanilla light UV");
        var blank=SignGlyphRaster.render(bounds,4,List.of(),List.of(),new float[]{1,1,1});
        check(blank.getWidth()==8 && blank.getRGB(0,0)==0,"empty sign has transparent surface");
        System.out.println("PASS: font shader sampling, diagonal alpha, atlas rows, outline, lightmap, empty surfaces");
    }
}
