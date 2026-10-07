"""One focused truth-dispatch fixture; no actual receipt/state/Saved is read."""
import ast
from pathlib import Path
D=Path(__file__).resolve().parents[1]
def condition(layer,first):
 tree=ast.parse((D/layer/'launcher/journal_lifecycle.py').read_text())
 fn=next(n for n in tree.body if isinstance(n,ast.FunctionDef)and n.name=='prepare_cold_boot')
 node=next(n for n in ast.walk(fn)if isinstance(n,ast.IfExp)and isinstance(n.body,ast.UnaryOp)
  and isinstance(n.body.operand,ast.Call)and isinstance(n.body.operand.func,ast.Name)and n.body.operand.func.id==first)
 return compile(ast.Expression(body=node),'exact-coldboot-truth-dispatch','eval')
old=condition('base','_saved_crash_receipt_matches');new=condition('source','_unsaved_crash_receipt_matches')
def run(expr,unsaved,saved,title,native_ok=True):
 calls=[]
 def u(*args):calls.append('unsaved');return native_ok
 def s(*args):calls.append('saved');return native_ok
 result=eval(expr,dict(_unsaved_crash_receipt_matches=u,_saved_crash_receipt_matches=s,
  unsaved_crash=unsaved,saved_crash=saved,root=None,scope=None,previous=None,
  receipt={'normal_title_Quit_and_native_exit0':title}))
 return result,calls
assert run(old,True,False,False)==(True,[]) # Exact original contradiction reproduced.
assert run(new,True,False,False)==(False,['unsaved'])
assert run(new,True,False,False,False)==(True,['unsaved'])
for args in [(False,True,False),(False,True,False,False),(False,False,True),(False,False,False)]:
 assert run(old,*args)==run(new,*args),'Original saved/normal truth changed'
before=(D/'base/launcher/journal_lifecycle.py').read_text()
after=(D/'source/launcher/journal_lifecycle.py').read_text()
added="or (not _unsaved_crash_receipt_matches(root, scope, previous, receipt) if unsaved_crash\n                     else not _saved_crash_receipt_matches(root, scope, previous, receipt) if saved_crash\n"
original="or (not _saved_crash_receipt_matches(root, scope, previous, receipt) if saved_crash\n"
assert after.replace(added,original)==before
assert 'inventory = _crash_persistent_inventory if unsaved_crash else _persistent_inventory' in after
print('PASS1 targeted exact AST dispatch: v24 unsaved-FalseTitle contradiction reproduced; valid unsaved matcher selected/accepted, wrong-native matcher rejected; saved/normal decisions and recorded calls identical. BOM/inventory/all remaining bytes unchanged. No actual receipt or Saved read.')
