import java.nio.file.*;
import java.util.*;
import java.util.zip.*;
import org.objectweb.asm.*;

/** Compile dependency only. Mirrors the two interfaces installed by the existing Fabric networking mixins. */
public final class FabricCompileInterfaces {
    public static void main(String[] args) throws Exception {
        String context="net/fabricmc/fabric/api/networking/v1/context/PacketContextProvider";
        try(ZipFile input=new ZipFile(args[0]);ZipOutputStream output=new ZipOutputStream(Files.newOutputStream(Path.of(args[1])))){
            for(String target:List.of("ServerCommonPacketListenerImpl","ServerLoginPacketListenerImpl")){
                String name="net/minecraft/server/network/"+target+".class";
                ClassWriter writer=new ClassWriter(0);
                new ClassReader(input.getInputStream(input.getEntry(name))).accept(new ClassVisitor(Opcodes.ASM9,writer){
                    @Override public void visit(int version,int access,String name,String signature,String parent,String[] interfaces){
                        List<String> declared=new ArrayList<>(Arrays.asList(interfaces));
                        if(!declared.contains(context))declared.add(context);
                        super.visit(version,access,name,signature,parent,declared.toArray(String[]::new));
                    }
                },0);
                output.putNextEntry(new ZipEntry(name));output.write(writer.toByteArray());output.closeEntry();
            }
        }
    }
}
