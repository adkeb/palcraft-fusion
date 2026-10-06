public final class OverlayFloatOracle {
    public static void main(String[] args) {
        StringBuilder result=new StringBuilder("{\"alpha_lut\":[");
        for(int u=0;u<16;u++) {
            if(u>0)result.append(',');
            result.append((int)((1-(float)u/15.0F*0.75F)*255.0F));
        }
        result.append("],\"source\":\"actual OverlayTexture bytecode float operations\",\"gpu_calls\":0}");
        System.out.println(result);
    }
}
