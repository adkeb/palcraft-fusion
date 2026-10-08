package dev.rehan.passthrough;

import java.util.ArrayList;
import java.util.IdentityHashMap;
import java.util.Map;
import java.util.function.Consumer;
import java.util.function.Predicate;

/** Load callbacks enqueue only; the owning server's END tick drains a detached snapshot. */
public final class DeferredEntityCleanup<S,L,I,E> {
    public record Entry<S,L,I,E>(S server,L level,I id,E entity){}
    private final Map<E,Entry<S,L,I,E>> pending=new IdentityHashMap<>();
    public void enqueue(S server,L level,I id,E entity){pending.put(entity,new Entry<>(server,level,id,entity));}
    public void drain(S server,Predicate<Entry<S,L,I,E>> stillEligible,Consumer<E> discard){
        var batch=new ArrayList<>(pending.values());
        for(var entry:batch){
            if(entry.server()!=server)continue;
            pending.remove(entry.entity());
            if(stillEligible.test(entry))discard.accept(entry.entity());
        }
    }
    public void clear(){pending.clear();}
    public int size(){return pending.size();}
}
