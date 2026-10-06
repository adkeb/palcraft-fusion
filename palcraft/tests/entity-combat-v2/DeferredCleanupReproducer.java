import dev.rehan.passthrough.DeferredEntityCleanup;
import java.util.*;

/** A load callback removes from the same section ArrayList being traversed; fixed code enqueues only. */
public final class DeferredCleanupReproducer {
    private static int assertions;
    private static void check(boolean yes){assertions++;if(!yes)throw new AssertionError("assertion "+assertions);}
    private record FakeEntity(UUID id,boolean stale){}
    public static void main(String[] args){
        Object server=new Object(),otherServer=new Object(),level=new Object();
        List<FakeEntity> broken=new ArrayList<>(List.of(new FakeEntity(UUID.randomUUID(),true),new FakeEntity(UUID.randomUUID(),true),new FakeEntity(UUID.randomUUID(),false)));
        boolean cme=false;
        try{for(Iterator<FakeEntity> it=broken.iterator();it.hasNext();){FakeEntity e=it.next();if(e.stale())broken.remove(e);}}catch(ConcurrentModificationException expected){cme=true;}
        check(cme);
        List<FakeEntity> section=new ArrayList<>(List.of(new FakeEntity(UUID.randomUUID(),true),new FakeEntity(UUID.randomUUID(),true),new FakeEntity(UUID.randomUUID(),false)));
        var queue=new DeferredEntityCleanup<Object,Object,UUID,FakeEntity>();
        // Equivalent section stream -> ENTITY_LOAD callback. No collection mutation until traversal returns.
        section.stream().forEach(e->{if(e.stale())queue.enqueue(server,level,e.id(),e);});
        check(section.size()==3&&queue.size()==2);
        queue.drain(otherServer,e->true,section::remove);check(section.size()==3&&queue.size()==2);
        queue.drain(server,e->e.level()==level&&section.stream().anyMatch(v->v==e.entity())&&e.id().equals(e.entity().id())&&e.entity().stale(),section::remove);
        check(section.size()==1&&!section.getFirst().stale()&&queue.size()==0);
        FakeEntity claimed=new FakeEntity(UUID.randomUUID(),true);section.add(claimed);queue.enqueue(server,level,claimed.id(),claimed);
        queue.drain(server,e->false,section::remove);check(section.contains(claimed)&&queue.size()==0);
        FakeEntity old=new FakeEntity(UUID.randomUUID(),true),replacement=new FakeEntity(old.id(),false);section.add(replacement);queue.enqueue(server,level,old.id(),old);
        queue.drain(server,e->section.stream().anyMatch(v->v==e.entity()),section::remove);check(section.contains(replacement));
        queue.enqueue(server,level,old.id(),old);queue.enqueue(server,level,old.id(),old);check(queue.size()==1);
        FakeEntity later=new FakeEntity(UUID.randomUUID(),true);section.add(old);section.add(later);
        queue.drain(server,e->true,e->{section.remove(e);queue.enqueue(server,level,later.id(),later);});
        check(queue.size()==1&&section.contains(later));queue.clear();check(queue.size()==0);
        System.out.println("{\"ok\":true,\"suite\":\"deferred_section_cleanup_reproducer\",\"old_inline_cme_reproduced\":true,\"deferred_traversal_completed\":true,\"assertions\":"+assertions+",\"real_minecraft_runtime_test\":false,\"execution_mode\":\"night_low_power\"}");
    }
}
