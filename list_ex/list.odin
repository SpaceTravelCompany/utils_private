package list_ex

import li "core:container/intrusive/list"

insert_after :: proc "contextless" (list: ^li.List, current_node: ^li.Node, new_node: ^li.Node) {
    if new_node != nil && current_node != nil {
        new_node.prev = current_node
		new_node.next = current_node.next

        if current_node.next != nil {  
			current_node.next.prev = new_node
        } else {
            list.tail = new_node
        }
        current_node.next = new_node
    }
}

insert_before :: proc "contextless" (list: ^li.List, current_node: ^li.Node, new_node: ^li.Node) {
    if new_node != nil && current_node != nil {
        new_node.next = current_node
		new_node.prev = current_node.prev

        if current_node.prev != nil {
			current_node.prev.next = new_node
        } else {
            list.head = new_node
        }
        current_node.prev = new_node
    }
}